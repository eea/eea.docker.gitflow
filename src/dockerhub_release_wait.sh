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

if [ ! -z "$3" ]; then
   echo "Received trigger parameter, will try to start build if not found"
   DOCKERHUB_TRIGGER=$3
fi


if [ -z "$DOCKERHUB_REPO" ] ||  [ -z "$DOCKERHUB_NAME" ]; then
  echo "Did not receive correct arguments - docker image name and version"
  exit 1
fi


    echo "-------------------------------------------------------------------------------"
    wait_in_case_of_error=15
    echo "Wait $TIME_TO_WAIT_START *10 seconds for the build $DOCKERHUB_REPO:$DOCKERHUB_NAME to be started on DockerHub"

    while [ $TIME_TO_WAIT_START  -ge 0 ]; do
        sleep 10
        TIME_TO_WAIT_START=$(( $TIME_TO_WAIT_START - 1 ))
        FOUND_BUILD=$( curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/ | grep -E ".*\"status\": [0-9]+,.*\"dockertag_name\": \"$DOCKERHUB_NAME\".*" | wc -l )

        if [ $FOUND_BUILD -gt 0 ];then
          echo "DockerHub started the $DOCKERHUB_REPO:$DOCKERHUB_NAME release"
          break
        fi
        if [ ! -z "$DOCKERHUB_TRIGGER" ] && ! (( TIME_TO_WAIT_START % 10 )); then
            echo "One minute passed, build not starting , will use trigger to re-start build"
            curl -i -H "Content-Type: application/json" --data "{\"source_type\": \"Tag\", \"source_name\": \"$DOCKERHUB_NAME\"}" -X POST https://registry.hub.docker.com/u/$DOCKERHUB_REPO/trigger/$DOCKERHUB_TRIGGER/
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
        buildhistory=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/)
        dockerhub_down=30
        while [ $(echo "$buildhistory" | grep -c "dockertag_name" ) -eq 0 ] && [ $dockerhub_down -gt 0 ]; do
           echo "Received unexpected response from DockerHub"
           echo "$buildhistory"
           buildhistory=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/)
           sleep 60
           dockerhub_down=$(( $dockerhub_down - 1 ))
        done

         if [ $dockerhub_down -eq 0 ]; then
            echo "DockerHub down more than 30 minutes, exiting"
            exit 1
         fi

        build_status=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/ | python -c "import sys, json
data_dict = json.load(sys.stdin)
dockertag_name = '$DOCKERHUB_NAME'
for res in data_dict['results']:
    if res['dockertag_name'] == dockertag_name:
        print '%s' % res['status']
        break
")
        if [ $build_status -lt 0 ] && [ $wait_in_case_of_error -gt 0 ]; then
         echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME failed on DockerHub, will wait $wait_in_case_of_error in case it will be ok"
         wait_in_case_of_error=$(( $wait_in_case_of_error - 1 ))
        fi

        if [ $build_status -lt 0 ] && [ $wait_in_case_of_error -eq 0 ]; then
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


