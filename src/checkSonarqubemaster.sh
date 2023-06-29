#!/bin/bash

set -e

GIT_ORG=${GIT_ORG:-'eea'}
SONAR_HOST_URL=${SONAR_HOST_URL:-https://sonarqube.eea.europa.eu/}

if [ -z "$GIT_NAME" ]; then
   echo "Need GIT_NAME environment variable"
   exit 1
fi


if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi

develop_stats=$(curl -s "${SONAR_HOST_URL}api/measures/component?component=$GIT_NAME-develop&metricKeys=bugs,security_rating,sqale_rating,coverage,duplicated_lines_density" | jq )
master_stats=$(curl -s "${SONAR_HOST_URL}api/measures/component?component=$GIT_NAME-master&metricKeys=bugs,security_rating,sqale_rating,coverage,duplicated_lines_density" | jq  )


while [ $(echo $develop_stats | grep bugs | wc -l) -eq 0 ] && [ $(echo $develop_stats | grep -i "not found" | wc -l) -eq 0 ]; do
      sleep 10
      develop_stats=$(curl -s "${SONAR_HOST_URL}api/measures/component?component=$GIT_NAME-develop&metricKeys=bugs,security_rating,sqale_rating,coverage,duplicated_lines_density" | jq )
done

if [ $(echo $develop_stats | grep -i "not found" | wc -l) -ne 0 ]; then 
	echo "DID not find develop project"
	echo $develop_stats
	exit
fi


master_stats=$(curl -s "${SONAR_HOST_URL}api/measures/component?component=$GIT_NAME-master&metricKeys=bugs,security_rating,sqale_rating,coverage,duplicated_lines_density" | jq  )

while [ $(echo $master_stats | grep bugs | wc -l) -eq 0 ] && [ $(echo $master_stats | grep -i "not found" | wc -l) -eq 0 ]; do
      sleep 10
      master_stats=$(curl -s "${SONAR_HOST_URL}api/measures/component?component=$GIT_NAME-master&metricKeys=bugs,security_rating,sqale_rating,coverage,duplicated_lines_density" | jq )
done

if [ $(echo $master_stats | grep -i "not found" | wc -l) -ne 0 ]; then
        echo "DID not find master project"
        exit
fi

exit_error=0

#check bugs | must be 0

bugs=$(echo "$develop_stats" | jq  -r '.component.measures[] | select( .metric == "bugs") | .value')
if [ "$bugs" -ne 0 ]; then
	echo "There are $bugs bugs in the develop branch"
	echo "Please check the sonarqube link and fix them: ${SONAR_HOST_URL}project/issues?resolved=false&types=BUG&inNewCodePeriod=false&id=$GIT_NAME-develop"
        exit_error=1
fi

#check vulnerabilities | must be <=

vul_develop=$(echo "$develop_stats" | jq  -r '.component.measures[] | select( .metric == "security_rating") | .value|tonumber')
vul_master=$(echo "$master_stats" | jq  -r '.component.measures[] | select( .metric == "security_rating") | .value|tonumber')

if [ "$vul_master" -lt "$vul_develop" ]; then
        echo "The security rating is worse in the develop branch ($vul_develop) than the master ($vul_master) branch"
        echo "Please check the sonarqube link and fix this: ${SONAR_HOST_URL}project/issues?resolved=false&types=VULNERABILITY&inNewCodePeriod=false&id=$GIT_NAME-develop"
        exit_error=1
fi


#check maintainability | code smells | must be <=

vul_develop=$(echo "$develop_stats" | jq  -r '.component.measures[] | select( .metric == "sqale_rating") | .value|tonumber')
vul_master=$(echo "$master_stats" | jq  -r '.component.measures[] | select( .metric == "sqale_rating") | .value|tonumber')

if [ "$vul_master" -lt "$vul_develop" ]; then
        echo "The maintainability rating is worse in the develop branch ($vul_develop) than the master ($vul_master) branch"
        echo "Please check the sonarqube link and fix this: ${SONAR_HOST_URL}/component_measures?id=$GIT_NAME-develop&metric=sqale_rating&view=list"
        exit_error=1
fi



#check duplicated_lines_density | must be smaller

vul_develop=$(echo "$develop_stats" | jq  -r '.component.measures[] | select( .metric == "duplicated_lines_density") | .value|tonumber * 100')

vul_master=$(echo "$master_stats" | jq  -r '.component.measures[] | select( .metric == "duplicated_lines_density") | .value|tonumber * 100')

if [ "$vul_master" -lt "$vul_develop" ]; then
        echo "The percentage of duplicated lines is bigger in the develop branch ($vul_develop) than the master ($vul_master) branch"
        echo "Please check the sonarqube link and fix this: ${SONAR_HOST_URL}/component_measures?id=$GIT_NAME-develop&metric=duplicated_lines_density&view=list"
        exit_error=1
fi




#check coverage | must be better

vul_develop=$(echo "$develop_stats" | jq  -r '.component.measures[] | select( .metric == "coverage") | .value|tonumber * 100')
vul_master=$(echo "$master_stats" | jq  -r '.component.measures[] | select( .metric == "coverage") | .value|tonumber * 100')

if [ "$vul_master" -gt "$vul_develop" ]; then
	echo "The percentage of coverage is smaller in the develop branch ($vul_develop) than the master ($vul_master) branch"
        echo "Please check the sonarqube link and fix this: ${SONAR_HOST_URL}/component_measures?id=$GIT_NAME-develop&metric=coverage&view=list"
        exit_error=1
fi



exit $exit_error
