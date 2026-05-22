#!/bin/bash

echo "Starting script that updated fleet.yaml files on latest helm chart $HELM_CHART"


if [ -z "$GIT_TOKEN" ]; then
  echo "Script NEEDS GIT_TOKEN variable to be able to run"
  exit 1
fi

#mandatory to get
if [ -z "$HELM_CHART" ]; then
  echo "This script needs HELM_CHART"
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


export GITHUB_TOKEN="${GIT_TOKEN}"

RANCHER_HELM_GITNAME=${RANCHER_HELM_GITNAME:-'helm-charts'}
RANCHER_FLEET_GITNAME=${RANCHER_FLEET_GIT:='eea-fleet'}
RANCHER_FLEET_GITSRC=https://$GIT_USER:$GITHUB_TOKEN@github.com/${GIT_ORG}/${RANCHER_FLEET_GITNAME}.git

if [ -z "$HELM_NEWVERSION" ]; then
  rm -f Chart.yaml
  wget https://raw.githubusercontent.com/$GIT_ORG/$RANCHER_HELM_GITNAME/refs/heads/main/sources/$HELM_CHART/Chart.yaml
  HELM_NEWVERSION=$( grep '^version:' Chart.yaml | awk '{print $2}' | sed 's/"//g' | sed "s/'//g" ) 
fi
new_version="${HELM_NEWVERSION}"

echo "Starting update of fleet yamls from ${GIT_ORG}/${RANCHER_FLEET_GITNAME}" 

if [ ! -d ${RANCHER_FLEET_GITNAME} ]; then
     git clone $RANCHER_FLEET_GITSRC
     cd ${RANCHER_FLEET_GITNAME}
else
     cd ${RANCHER_FLEET_GITNAME}
     git pull
fi



for i in $(find apps/ -name fleet.yaml); do 
	
	fl_helm_chart=$(yq -r '.helm.chart' $i)

      if [[ "$HELM_CHART" == "$fl_helm_chart" ]]; then

	echo "Found fleet file $i"

        echo "Starting update on $i"
        old_version=$( yq ".helm.version" $i)
        if [[ $(is_smaller "$old_version" "$new_version") == "False" ]]; then
              echo "Current version of HELM Chart - $old_version is bigger than $new_version , so will skip upgrade"
        else
              echo "Current version of HELM Chart  $old_version is smaller than $new_version , starting upgrade" 
              yq -i ".helm.version = $new_version"  $i

  	fi
    fi
done

echo "git diff:"
        git diff .
        if [ $( git diff . | wc -l ) -gt 0 ]; then
            git add .	
            git commit -m "chore: Automated update on $HELM_CHART:$new_version"
	    git push
        else
	    echo "Nothing to update"
 	fi







