#!/bin/bash

set -e

GIT_ORG=${GIT_ORG:-'eea'}
RANCHER_HELM_GITNAME=${RANCHER_HELM_GITNAME:-'helm-charts'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
HELM_INDEX=${HELM_INDEX:-'https://eea.github.io/helm-charts/index.yaml'}


if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to create releases"
   exit 1
fi

if [ "$#" -ge 2 ]; then
       echo "Received parameters from argument, will parse them "
       DOCKER_IMAGENAME=$1
       DOCKER_IMAGEVERSION=$2
fi

if [ -z "$DOCKER_IMAGENAME" ] || [ -z "$DOCKER_IMAGEVERSION" ]; then
       echo "Problem with creating helm chart entry, missing parameters"
       exit 1
fi

echo "Checked parameters, will start creating helm chart entry on ${GIT_ORG}/${RANCHER_HELM_GITNAME}, helm chart ${HELM_CHART} for ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"

RANCHER_HELM_GITSRC=https://$GIT_USER:$GIT_TOKEN@github.com/${GIT_ORG}/${RANCHER_HELM_GITNAME}.git
git config --global user.email "${GIT_USER}@users.noreply.github.com"
git config --global user.name "${GIT_USERNAME}"



export CI="yes"

DOCKER_IMAGENAME_ESC=$(echo $DOCKER_IMAGENAME | sed 's/\//\\\//g')
GITHUBURL=https://api.github.com/repos/${GIT_ORG}/${RANCHER_HELM_GITNAME}/git
current_dir=$(pwd)

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi

# clone the repo
rm -rf $RANCHER_HELM_GITNAME
git clone $RANCHER_HELM_GITSRC

cd ${RANCHER_HELM_GITNAME}



echo "Checked parameters, will start creating helm chart entry on ${GIT_ORG}/${RANCHER_HELM_GITNAME}, helm chart ${HELM_CHART} for ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"

if [ -n "$HELM_CHART" ]; then
	list_sources=$HELM_CHART
else
	list_sources=$(grep -R $DOCKER_IMAGENAME sources/ | awk -F: '{print $1}' | awk -F"/" '{print $2}' | uniq )
fi

for i in $(echo $list_sources); do

	export HELM_UPGRADE_MESSAGE="Automated release of ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"
        export HELM_COMMIT_MESSAGE="Auto release of ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"       

	if [ -n "$GIT_NAME" ]; then
		export HELM_UPGRADE_MESSAGE="Automated release of [${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}](https://github.com/${GIT_ORG}/${GIT_NAME}/releases)"
	fi

	echo "Checking $i"
        export HELM_VERSION_TYPE="PATCH"
         
	cd sources/$i
	if [[ "$( yq '.image.repository' values.yaml )" == "$DOCKER_IMAGENAME" ]] || [[ "$HELM_UPGRADE_APPVERSION" == "yes" ]] ; then

		echo "Found $DOCKER_IMAGENAME as main application image or received HELM_UPGRADE_APPVERSION parameter"
                old_version=$( yq ".appVersion" Chart.yaml)

	        if [[ $(is_smaller "$old_version" "$DOCKER_IMAGEVERSION") == "False" ]]; then
	            echo "Current version of Chart - $old_version is bigger than $DOCKER_IMAGEVERSION , so will skip upgrade"
		else
		    echo "Current version of Chart  $old_version is smaller than $DOCKER_IMAGEVERSION , starting upgrade" 
	            
		    yq -i ".appVersion = \"$DOCKER_IMAGEVERSION\""  Chart.yaml

		    if [[ "$DOCKER_IMAGEVERSION" == *"beta"* ]]; then
			   echo "New version is beta, will create a PATCH release"
			   export HELM_VERSION_TYPE="PATCH"
            else
		       export HELM_VERSION_TYPE="MINOR"
			fi
		fi

	fi


        if [[ "$HELM_UPGRADE_APPVERSION" == "yes" ]]; then
                echo "Received HELM_UPGRADE_APPVERSION parameter, will not upgrade version in values nor templates, as helm chart will use appVersion as default tag"
	else
		#comments are not allowed in values.yaml
		sed -i "s|$DOCKER_IMAGENAME:[0-9]+.*|$DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION|g" values.yaml

		# don't update version when gitflow-disable is on the same line
		sed -i -e "/gitflow-disable/! s/    image: ${DOCKER_IMAGENAME_ESC}:[0-9].*$/    image: ${DOCKER_IMAGENAME_ESC}:${DOCKER_IMAGEVERSION}/"  templates/*.yaml
	fi

	if [ $( git diff . | wc -l ) -gt 0 ]; then
      	  ../../increase_version_helm.sh

	  cd ../..

          ./update_docs.sh $i

          echo "Wait for the charts to update"
          sleep 20
               
        else
	  cd ../..
        fi

        HELM_NEWVERSION=$(yq ".version"  sources/$i/Chart.yaml)

        echo "Will now check if chart $i:$HELM_NEWVERSION is released, then update subcharts"
      
	rm -rf index.yaml
	wget $HELM_INDEX
	timeout=1200

	while [ $(yq '.entries.'$i'[] | select ( .version == "'$HELM_NEWVERSION'") ' index.yaml | wc -l ) -eq 0 ] && [ $timeout -gt 0 ]; do
		  sleep 20
		  let timeout=timeout-20
		  rm -rf index.yaml
                  wget $HELM_INDEX
        done
            
	if [ $timeout -le 0 ]; then
		  echo "The index was not updated in time, will skip subchart update"
	          exit 1
	fi

	echo "The index was updated with the release"

	echo "Updating related charts from helm-charts, if found"


	./release_subchart.sh $i

       
	

done

