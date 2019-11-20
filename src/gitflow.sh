#!/bin/bash

set -e

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to create releases"
   exit 1
fi

if [ -f /common_functions ]; then
    source /common_functions
elif [ -f ./common_functions ]; then
    source ./common_functions
fi


if [ -z "$DOCKERHUB_REPO" ] || [ -z "$GIT_NAME" ]; then
   echo "You need to provide the GIT_NAME and DOCKERHUB_REPO environment variables to create releases"
   exit 1
fi



git clone $GIT_SRC
cd $GIT_NAME

# Image release on DockerHub
if [[ "$GIT_BRANCH" == "master" ]]; then

    git fetch --tags
    get_last_tag

    files_changed=$(git --no-pager diff --name-only master $(git merge-base $latestTag  master) | wc -l )

    if [ $files_changed -eq 0 ]; then
      echo "No files changed since last release, $latestTag"
      exit 0
    fi

    echo "-------------------------------------------------------------------------------"
    echo "Found $files_changed files changed since last release ($latestTag)"
    version=$(echo $latestTag + 0.1 | bc)

    echo "Version is $version"

    echo "-------------------------------------------------------------------------------"
    echo "Starting the release $version"
    curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

    if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
      echo "There was a problem with the release"
      echo $curl_result
      exit 1
    fi
    echo "-------------------------------------------------------------------------------"

    /dockerhub_release_wait.sh ${DOCKERHUB_REPO} $version


    echo "-------------------------------------------------------------------------------"
    echo "Starting the Rancher catalog release"

  
    for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
 	/add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH $DOCKERHUB_REPO $version $RANCHER_CATALOG_SAME_VERSION 
    done

fi

exec "$@"
