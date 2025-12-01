#!/bin/bash

echo "Starting script that checks github releases on official images and updates them in our helm-charts"


if [ -z "$GIT_TOKEN" ]; then
  echo "Script NEEDS GIT_TOKEN variable to be able to run"
  exit 1
fi

#mandatory to get
if [ -z "$HELM_CHART" ] || [ -z "$DOCKER_IMAGENAME" ] || [ -z "$GITHUB_RELEASES" ]; then
  echo "This script needs HELM_CHART, DOCKER_IMAGENAME and GITHUB_RELEASES to work"
  echo "RELEASE_PREFIX and RELEASE_SUFFIX are not mandatory"
fi



if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi


GIT_ORG=${GIT_ORG:-'eea'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}

#forces script to only update main version
export HELM_UPGRADE_APPVERSION="yes"

export GITHUB_TOKEN="${GIT_TOKEN}"

RANCHER_HELM_GITNAME=${RANCHER_HELM_GITNAME:-'helm-charts'}

# just in case
rm -rf Chart.yaml 
wget https://raw.githubusercontent.com/$GIT_ORG/$RANCHER_HELM_GITNAME/refs/heads/main/sources/$HELM_CHART/Chart.yaml

current_version=$( grep 'appVersion' Chart.yaml | awk '{print $2}' | sed 's/"//g' | sed "s/'//g" )


echo "Current app version of $HELM_CHART helm chart is $current_version)"

releases=$(curl -s -X GET -L -H "Authorization: bearer $GIT_TOKEN"  $GITHUB_RELEASES )

last_release=$(echo "$releases" |  jq -r '.[].tag_name' | head -n 1)

echo "Last release in github is $last_release)"

if [[ "${RELEASE_PREFIX}${last_release}${RELEASE_SUFFIX}" == "$current_version" ]]; then
	echo "It is already updated in Helm Charts, finishing"
        exit 0
fi

echo "Starting update helm chart script"

/add_helm_chart_entry.sh   $DOCKER_IMAGENAME ${RELEASE_PREFIX}${last_release}${RELEASE_SUFFIX}

