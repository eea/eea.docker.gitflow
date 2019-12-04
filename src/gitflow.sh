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
      echo "Will continue without the release on github"
      version=$latestTag
    else
      echo "-------------------------------------------------------------------------------"
      echo "Found $files_changed files changed since last release ($latestTag)"
      version=$(echo $latestTag + 0.1 | bc)

      echo "Version is $version"

      echo "-------------------------------------------------------------------------------"
      echo "Starting the release $version"
      curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

      if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
        echo "There was a problem with the release"
        echo "https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases"
	echo "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"
	echo $curl_result
        exit 1
      fi
    fi

    echo "-------------------------------------------------------------------------------"

    /dockerhub_release_wait.sh ${DOCKERHUB_REPO} $version


    echo "-------------------------------------------------------------------------------"
    echo "Starting the Rancher catalog release"
    
    if [ -z "$RANCHER_CATALOG_PATHS" ]; then
         cd /
         git clone https://github.com/${GIT_ORG}/${RANCHER_CATALOG_GITNAME}.git
         cd ${RANCHER_CATALOG_GITNAME}
         RANCHER_CATALOG_PATHS=$(for i in $(grep ${DOCKERHUB_REPO}: */*/*/docker-compose* | awk -F'[ /]' '{print $1"/"$2}' | uniq); do grep -l ${DOCKERHUB_REPO}: $i"/"$(find $i  -maxdepth 1 -type d  | awk  'BEGIN{FS="/"}{print $3}' | sort -n | tail -n 1)/docker-compose*; done | awk -F'/' '{print $1"/"$2}') 
         cd /
         rm -rf ${RANCHER_CATALOG_GITNAME}
    fi
    
    for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
      	/add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH $DOCKERHUB_REPO $version $RANCHER_CATALOG_SAME_VERSION 
    done

fi

exec "$@"
