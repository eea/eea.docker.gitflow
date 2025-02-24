#!/bin/bash

set -e

GIT_ORG=${GIT_ORG:-'eea'}
RANCHER_HELM_GITNAME=${RANCHER_CATALOG_GITNAME:-'helm-charts'}

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to create releases"
   exit 1
fi


if [ -z "$DOCKER_IMAGENAME" ] || [ -z "$DOCKER_IMAGEVERSION" ]; then
   if [ "$#" -ge 3 ]; then
       echo "Did not receive parameters from environment, will try to parse them from arguments"
       HELM_CHART=$1
       DOCKER_IMAGENAME=$2
       DOCKER_IMAGEVERSION=$3
   else
       echo "Problem with creating helm chart entry, missing parameters"
       exit 1
   fi
fi

echo "Checked parameters, will start creating helm chart entry on ${GIT_ORG}/${RANCHER_HELM_GITNAME}, helm chart ${HELM_CHART} for ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"

RANCHER_HELM_GITSRC=https://$GIT_USER:$GIT_TOKEN@github.com/${GIT_ORG}/${RANCHER_HELM_GITNAME}.git

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

list_sources=$(grep -R $DOCKER_IMAGENAME sources/ | awk -F: '{print $1}' | awk -F"/" '{print $2}' | uniq )

for i in $(echo $list_sources); do

        export HELM_UPGRADE_MESSAGE="Automated release of ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"
	
	echo "Checking $i"
        export HELM_VERSION_TYPE="PATCH"
         
	cd sources/$i
	if [[ "$( yq '.image.repository' values.yaml )" == "$DOCKER_IMAGENAME" ]]; then

		echo "Found $DOCKER_IMAGENAME as main application image"
	        yq -i ".appVersion = \"$DOCKER_IMAGEVERSION\""  Chart.yaml
                export HELM_VERSION_TYPE="MINOR"

	fi

        #comments are not allowed in values.yaml
        sed -i "s|$DOCKER_IMAGENAME:[0-9]+.*|$DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION|g" values.yaml


        # don't update version when gitflow-disable is on the same line
        sed -i -e "/gitflow-disable/! s/    image: ${DOCKER_IMAGENAME_ESC}:[0-9]+.*$/    image: ${DOCKER_IMAGENAME_ESC}:${DOCKER_IMAGEVERSION}/"  templates/*.yaml

	if [ $( git diff . | wc -l ) -gt 0 ]; then
      	  ../../increase_version_helm.sh

	  cd ../..

          ./update_docs.sh $i

	  echo "Updating related charts from helm-charts, if found"

	  ./release_subchart.sh $i
	
	 else
          cd  ../..
	fi

done

