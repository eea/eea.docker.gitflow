#!/bin/bash

set -e

git clone $GIT_SRC
cd $GIT_NAME

# WWW release
if [[ "$GIT_BRANCH" == "master" ]]; then

        latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
        dockerfile_changed=$(git --no-pager diff --name-only master $(git merge-base $latestTag  master) | grep -c  "^Dockerfile$" )
        

      if [ $dockerfile_changed -eq 0 ]; then
       echo "Dockerfile not changed since last release, $latestTag"
       exit 0
      fi
     echo "-------------------------------------------------------------------------------"
     echo "Found $files_changed files changed since last release ($latestTag)"
     version=$(grep "FROM $DOCKERHUB_KGSREPO" Dockerfile | awk -F: '{print $2}')
 
      if [ $(git tag | grep -c "^$version$" ) -ne 0 ]; then
         echo "Pipeline aborted due to version $version already released"
         exit 1
        fi
 
     echo "New version is $version"
     echo "-------------------------------------------------------------------------------"

     echo "Starting the release $version"
     curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

     if [ $( echo $curl_result | grep -c  "HTTP/1.1 201 Created" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
     fi
     echo "-------------------------------------------------------------------------------"
     echo "Wait $TIME_TO_WAIT_START *10 seconds for the build to be started on DockerHub"
      while [ $TIME_TO_WAIT_START  -ge 0 ]; do
        sleep 10
        TIME_TO_WAIT_START=$(( $TIME_TO_WAIT_START - 1 ))
        FOUND_BUILD=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_WWWREPO}/buildhistory/?page_size=100 | grep -c "\"dockertag_name\": \"$version\"")
        if [ $FOUND_BUILD -gt 0 ];then
          echo "DockerHub started the $version release"
          break
        fi
      done
     if [ $TIME_TO_WAIT_START  -lt 0 ]; then
       echo "There was a problem in DockerHub, build not started!"
       exit 1
     fi
     echo "-------------------------------------------------------------------------------"
     echo "Waiting for the build to be finished on DockerHub"
     waiting=0
     while [ $TIME_TO_WAIT_RELEASE -ge 1 ]; do
        TIME_TO_WAIT_RELEASE=$(( $TIME_TO_WAIT_RELEASE - 1 ))
        waiting=$(( $waiting + 1 ))

        build_status=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_WWWREPO}/buildhistory/?page_size=100 | python -c "import sys, json
data_dict = json.load(sys.stdin)
dockertag_name = '$version'
for res in data_dict['results']:
    if res['dockertag_name'] == dockertag_name:
        print '%s' % res['status']
        break
")

        if [ $build_status -lt 0 ]; then
         echo "Build failed on DockerHub, please check it!!!"
         exit 1
        fi
        if [ $build_status -eq 10 ]; then
         echo "Build done succesfully on DockerHub"
         break
        fi
        if ! (( waiting % 5 )); then 
          echo "Waiting $waiting minutes, build still in progress on DockerHub (status $build_status)"
        fi
        sleep 60
     done

     if [ $TIME_TO_WAIT_RELEASE  -eq 0 ]; then
       echo "There was a problem in DockerHub, build not finished!"
       exit 1
     fi

     echo "-------------------------------------------------------------------------------"




fi

exec "$@"






