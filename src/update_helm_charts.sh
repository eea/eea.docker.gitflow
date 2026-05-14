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



#forces script to only update main version by default
export HELM_UPGRADE_APPVERSION="${HELM_UPGRADE_APPVERSION:-yes}"

export GITHUB_TOKEN="${GIT_TOKEN}"

RANCHER_HELM_GITNAME=${RANCHER_HELM_GITNAME:-'helm-charts'}
RANCHER_FLEET_GITNAME=${RANCHER_FLEET_GIT:='eea-fleet'}
RANCHER_FLEET_GITSRC=https://$GIT_USER:$GITHUB_TOKEN@github.com/${GIT_ORG}/${RANCHER_FLEET_GITNAME}.git

if [[ "$GITHUB_RELEASES" =~ /releases$ ]]; then
  type="tag_name"
elif [[ "$GITHUB_RELEASES" =~ /tags$ ]]; then
  type="name"
else
  echo "Unsupported endpoint: $GITHUB_RELEASES" >&2
  exit 1
fi

releases=$(curl -s -X GET -L -H "Authorization: bearer $GIT_TOKEN"  $GITHUB_RELEASES )

if [ -n "$GITHUB_RELEASE_REGEXP" ]; then
   echo "Will filter out releases with this regexp $GITHUB_RELEASE_REGEXP"
   last_release=$( echo "$releases" | jq -r --arg re "$GITHUB_RELEASE_REGEXP" --arg name "$type" '.[] | .[$name] | select(test($re))' | head -n 1 )
else
   last_release=$(echo "$releases" |  jq -r --arg name "$type"  '.[] | .[$name] ' | head -n 1)
fi

echo "Last release in github is $last_release"

mkdir -p /artifacts

if [ -n $DOCKER_ARTIFACT ]; then
   echo $last_release > /artifacts/$DOCKER_ARTIFACT
fi

if [ -n $DOCKER_ARTIFACT_CONTENT ]; then
   if [[ "$DOCKER_ARTIFACT_CONTENT" == "$last_release" ]]; then
     echo "Last succesfull job has already updated to $last_release"
	 echo "Exiting"
	 exit 0
   else
	echo "Last succesfull job has this artifact - $DOCKER_ARTIFACT_CONTENT and it is different from last release - $last_release"
   fi
fi


echo "Starting update helm chart script"

/add_helm_chart_entry.sh   $DOCKER_IMAGENAME ${RELEASE_PREFIX}${last_release}${RELEASE_SUFFIX}

cd /

if [ -n "$HELM_CHART" ]; then 
  rm -f Chart.yaml
  wget https://raw.githubusercontent.com/$GIT_ORG/$RANCHER_HELM_GITNAME/refs/heads/main/sources/$HELM_CHART/Chart.yaml
  new_version=$( grep '^version:' Chart.yaml | awk '{print $2}' | sed 's/"//g' | sed "s/'//g" ) 
  # FLEET_LOCATIONS - list of paths in the fleet repo, separated by space
  if [ -n "$FLEET_LOCATIONS" ]; then
  	cd /
        wget https://raw.githubusercontent.com/$GIT_ORG/$RANCHER_HELM_GITNAME/refs/heads/main/sources/$HELM_CHART/Chart.yaml
        new_version=$( grep '^version:' Chart.yaml | awk '{print $2}' | sed 's/"//g' | sed "s/'//g" )
        echo "Received FLEET_LOCATIONS parameter, will now update the fleet files with $HELM_CHART:$new_version"
        git clone RANCHER_FLEET_GITSRC
	cd RANCHER_FLEET_GITNAME
        echo "Starting update of fleet yamls from ${GIT_ORG}/${RANCHER_FLEET_GITNAME}" 
	for fleet in $FLEET_LOCATIONS; do
		echo "Starting update on $fleet/fleet.yaml"
 	        old_version=$( yq ".helm.version" $fleet/fleet.yaml)

                if [[ $(is_smaller "$old_version" "$new_version") == "False" ]]; then
                    echo "Current version of HELM Chart - $old_version is bigger than $new_version , so will skip upgrade"
                else
                    echo "Current version of HELM Chart  $old_version is smaller than $new_version , starting upgrade" 
	            yq -i ".helm.version = $new_version"  $fleet/fleet.yaml
		fi
	done
        
        git diff .
        if [ $( git diff . | wc -l ) -gt 0 ]; then
            git add .	
            git commit -m "chore: Automated update on $HELM_CHART:$new_version"
	    git push
        else
	    echo "Nothing to update"
 	fi
  fi

fi






