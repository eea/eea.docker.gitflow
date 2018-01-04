#!/bin/bash

set -e


if [ -z "$TIME_TO_WAIT_RELEASE" ]; then
  TIME_TO_WAIT_RELEASE=240
fi

if [ -z "$TIME_TO_WAIT_START" ]; then
  TIME_TO_WAIT_START=30
fi



DOCKERHUB_REPO=$1
DOCKERHUB_NAME=$2

if [ -z "$DOCKERHUB_REPO" ] ||  [ -z "$DOCKERHUB_NAME" ]; then
  echo "Did not receive correct arguments - docker image name and version"
  exit 1
fi
     

     echo "-------------------------------------------------------------------------------"
     
    echo "Wait $TIME_TO_WAIT_START *10 seconds for the build $DOCKERHUB_REPO:$DOCKERHUB_NAME to be started on DockerHub"
      while [ $TIME_TO_WAIT_START  -ge 0 ]; do
        sleep 10
        TIME_TO_WAIT_START=$(( $TIME_TO_WAIT_START - 1 ))
        FOUND_BUILD=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/?page_size=100 | grep -c "\"dockertag_name\": \"$DOCKERHUB_NAME\"")
        if [ $FOUND_BUILD -gt 0 ];then
          echo "DockerHub started the $DOCKERHUB_REPO:$DOCKERHUB_NAME release"
          break
        fi
      done
     if [ $TIME_TO_WAIT_START  -lt 0 ]; then
       echo "There was a problem in DockerHub, build $DOCKERHUB_REPO:$DOCKERHUB_NAME not started!"
       exit 1
     fi
     echo "-------------------------------------------------------------------------------"
     echo "Waiting for the build $DOCKERHUB_REPO:$DOCKERHUB_NAME  to be finished on DockerHub"
     waiting=0
     while [ $TIME_TO_WAIT_RELEASE -ge 1 ]; do
        TIME_TO_WAIT_RELEASE=$(( $TIME_TO_WAIT_RELEASE - 1 ))
        waiting=$(( $waiting + 1 ))

        build_status=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/?page_size=100 | python -c "import sys, json
data_dict = json.load(sys.stdin)
dockertag_name = '$DOCKERHUB_NAME'
for res in data_dict['results']:
    if res['dockertag_name'] == dockertag_name:
        print '%s' % res['status']
        break
")

        if [ $build_status -lt 0 ]; then
         echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME failed on DockerHub, please check it!!!"
         exit 1
        fi
        if [ $build_status -eq 10 ]; then
         echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME done succesfully on DockerHub"
         break
        fi
        if ! (( waiting % 5 )); then 
          echo "Waiting $waiting minutes, build still in progress on DockerHub (status $build_status)"
        fi
        sleep 60
     done

     if [ $TIME_TO_WAIT_RELEASE  -eq 0 ]; then
       echo "There was a problem in DockerHub, build $DOCKERHUB_REPO:$DOCKERHUB_NAME not finished!"
       exit 1
     fi

     echo "-------------------------------------------------------------------------------"


