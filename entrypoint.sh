#!/bin/bash

set -e


# if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
#   EVENT_ACTION=$(jq -r ".action" "${GITHUB_EVENT_PATH}")
#   if [[ "${EVENT_ACTION}" != "opened" ]]; then
#     echo "No need to run analysis. It is already triggered by the push event."
#     exit 78
#   fi
# fi

if [[ -z "${INPUT_PASSWORD}" ]]; then
	SONAR_PASSWORD=""
else
	SONAR_PASSWORD="${INPUT_PASSWORD}"
fi

sonar-scanner \
	-Dsonar.host.url=${INPUT_HOST} \
	-Dsonar.projectBaseDir=${INPUT_PROJECTBASEDIR} \
	-Dsonar.login=${INPUT_LOGIN} \
	-Dsonar.sources=. \
	-Dsonar.sourceEncoding=UTF-8
apk add jq
cat report-task.txt
SONAR_RESULT="report-task.txt"
SONAR_SERVER="${INPUT_HOST}"
SONAR_API_TOKEN="${INPUT_LOGIN}"

if [ ! -f $SONAR_RESULT ]
then
  echo "Sonar result does not exist"
  exit 1
fi

if [ -z $SONAR_API_TOKEN ]
then
  echo "Sonar API Token not set."
  exit 1
fi

CE_TASK_ID=`sed -n 's/ceTaskId=\(.*\)/\1/p' < $SONAR_RESULT` 
if [ -z $CE_TASK_ID ]
then
  echo "ceTaskId is not set from sonar build."
  exit 1
fi

DASHBOARD_URL=`sed -n 's/dashboardUrl=\(.*\)/\1/p' < $SONAR_RESULT` 
if [ -z $DASHBOARD_URL ]
then
  echo "DASHBOARD_URL is not set from sonar build."
  exit 1
fi

HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -u $SONAR_API_TOKEN: $SONAR_SERVER/api/ce/task\?id\=$CE_TASK_ID)
if [  "$HTTP_STATUS" -ne 200 ]
then
  echo "Sonar API Token has no access rights."
  exit 1
fi

ANALYSIS_ID=$(curl -XGET -s -u $SONAR_API_TOKEN: $SONAR_SERVER/api/ce/task\?id\=$CE_TASK_ID | jq -r .task.analysisId)
I=1
TIMEOUT=0
while [ $ANALYSIS_ID = "null" ]
do
  if [ "$TIMEOUT" -gt 30 ]
  then
    echo "Timeout of " + $TIMEOUT + " seconds exceeded for getting ANALYSIS_ID"
    exit 1
  fi
  sleep $I
  TIMEOUT=$((TIMEOUT+I))
  I=$((I+1))
  ANALYSIS_ID=$(curl -XGET -s -u $SONAR_API_TOKEN: $SONAR_SERVER/api/ce/task\?id\=$CE_TASK_ID | jq -r .task.analysisId)
done

STATUS=$(curl -XGET -s -u $SONAR_API_TOKEN: $SONAR_SERVER/api/qualitygates/project_status?analysisId=$ANALYSIS_ID | jq -r .projectStatus.status)
ERROR_STATUS=$(curl -XGET -s -u $SONAR_API_TOKEN: $SONAR_SERVER/api/qualitygates/project_status?analysisId=$ANALYSIS_ID | jq -r '.projectStatus.conditions[] | select(.status=="ERROR")')

ANALYSIS=$(curl -XGET -s -u $SONAR_API_TOKEN: $SONAR_SERVER/api/qualitygates/project_status?analysisId=$ANALYSIS_ID)
echo ::set-output name=analysis::$ANALYSIS
echo ::set-output name=status::$STATUS
echo ::set-output name=error_status::$ERROR_STATUS
echo ::set-output name=dashboard_url::$DASHBOARD_URL

if [ $STATUS = "ERROR" ]
then
  echo "Qualitygate failed."
  ERROR_DETAIL_MESSAGE="**Sonarqube Status Failed for Following Check**<br />$ERROR_STATUS<hr />**Review on Dashboard**<br />$DASHBOARD_URL"
  echo ::set-output name=error_detail_message::$ERROR_DETAIL_MESSAGE
  exit 0
fi 
echo "Sonar Qualitygate is OK."
exit 0
