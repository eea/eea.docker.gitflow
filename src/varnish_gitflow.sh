#!/bin/bash

set -e

git clone $GIT_SRC
cd $GIT_NAME

# Image release on DockerHub
if [[ "$GIT_BRANCH" == "master" ]]; then

    latestTag=$(git describe --tags)
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

    /dockerhub_release_wait.sh ${DOCKERHUB_VARNISHREPO} $version


    echo "-------------------------------------------------------------------------------"
    echo "Starting the Rancher catalog release"

    export RANCHER_CATALOG_PATH=templates/www-frontend
    export DOCKER_IMAGENAME=$DOCKERHUB_VARNISHREPO
    export DOCKER_IMAGEVERSION=$version
    export RANCHER_CATALOG_NEXT_VERSION=true
    /add_rancher_catalog_entry.sh

    echo "-------------------------------------------------------------------------------"
    export RANCHER_CATALOG_PATH=templates/www-eea
    export DOCKER_IMAGENAME=$DOCKERHUB_VARNISHREPO
    export DOCKER_IMAGEVERSION=$version
    export RANCHER_CATALOG_SAME_VERSION=true
    /add_rancher_catalog_entry.sh

fi

exec "$@"
