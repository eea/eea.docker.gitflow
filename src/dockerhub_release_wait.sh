#!/bin/bash

set -e


if [ -z "$TIME_TO_WAIT_RELEASE" ]; then
  TIME_TO_WAIT_RELEASE=240
fi

if [ -z "$TIME_TO_WAIT_START" ]; then
  TIME_TO_WAIT_START=30
fi

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi


DOCKERHUB_REPO=$1
DOCKERHUB_NAME=$2

if [ -n "$3" ]; then
   echo "Received trigger parameter, will try to start build if not found"
   DOCKERHUB_TRIGGER=$3
fi


if [ -z "$DOCKERHUB_USER" ] ||  [ -z "$DOCKERHUB_PASS" ]; then
  echo "Did not receive correct arguments - need dockerhub user and password to check build history"
  exit 1
fi



if [ -z "$DOCKERHUB_REPO" ] ||  [ -z "$DOCKERHUB_NAME" ]; then
  echo "Did not receive correct arguments - docker image name and version"
  exit 1
fi

echo "Starting dockerhub release wait script"

check_result=$(curl -s -X GET -H "Content-Type: application/json" "https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/tags/?page_size=100&name=${DOCKERHUB_NAME}" | grep "${DOCKERHUB_NAME}\"" | wc -l )

if [ $check_result -ne 0 ] && [[ -z "$GIT_COMMIT" ]]; then  
  echo "Found image already build in tags"
  exit 0
fi

    echo "-------------------------------------------------------------------------------"
    wait_in_case_of_error=15
    echo "Wait $TIME_TO_WAIT_START *10 seconds for the build $DOCKERHUB_REPO:$DOCKERHUB_NAME to be started on DockerHub"

    while [ $TIME_TO_WAIT_START  -ge 0 ]; do
        sleep 10
        TIME_TO_WAIT_START=$(( $TIME_TO_WAIT_START - 1 ))
        get_dockerhub_buildhistory ${DOCKERHUB_REPO}
        	
	if [ -n "$GIT_COMMIT" ]; then
            FOUND_BUILD=$( echo $buildhistory | jq  ".objects[] | select(.build_tag==\"$DOCKERHUB_NAME\" and .commit==\"$GIT_COMMIT\" and .state == (\"Failed\",\"Success\",\"Pending\",\"In progress\", \"Building\") ) | length" | wc -l )
	else
	    FOUND_BUILD=$( echo $buildhistory | jq  ".objects[] | select(.build_tag==\"$DOCKERHUB_NAME\" and .state == (\"Success\",\"Pending\",\"In progress\", \"Building\") ) | length" | wc -l )
        fi
	
        if [ $FOUND_BUILD -gt 0 ];then
          echo "DockerHub started the $DOCKERHUB_REPO:$DOCKERHUB_NAME release"
          break
	else
	  echo "DockerHub - can't find $DOCKERHUB_REPO:$DOCKERHUB_NAME"
        fi
        if [ -n "$DOCKERHUB_TRIGGER" ] && ! (( TIME_TO_WAIT_START % 10 )); then
            echo "Over one minute passed, build not starting , will use trigger to re-start build"

	    TRIGGER_TYPE="Tag"
	    TRIGGER_NAME="$DOCKERHUB_NAME"
	    if [ -n "$GIT_COMMIT" ]; then
                 TRIGGER_TYPE="Branch"
	    fi
	    if [[ "$DOCKERHUB_NAME" == "latest" ]]; then
                 TRIGGER_TYPE="Branch"
                 TRIGGER_NAME="master"
	    fi

            curl -i -H "Content-Type: application/json" --data "{\"source_type\": \"$TRIGGER_TYPE\", \"source_name\": \"$TRIGGER_NAME\"}" -X POST https://hub.docker.com/api/build/v1/source/$DOCKERHUB_TRIGGER
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
	get_dockerhub_buildhistory ${DOCKERHUB_REPO}
        dockerhub_down=30
        while [ $(echo "$buildhistory" | grep -c "build_tag" ) -eq 0 ] && [ $dockerhub_down -gt 0 ]; do
           echo "Received unexpected response from DockerHub"
           echo "$buildhistory"
           get_dockerhub_buildhistory ${DOCKERHUB_REPO}
           sleep 60
           dockerhub_down=$(( $dockerhub_down - 1 ))
        done

         if [ $dockerhub_down -eq 0 ]; then
            echo "DockerHub down more than 30 minutes, exiting"
            exit 1
         fi

         get_dockerhub_buildhistory ${DOCKERHUB_REPO}
	 
	 if [ -n "$GIT_COMMIT" ]; then
            build_status=$( echo $buildhistory | jq  -r ".objects[] | select(.build_tag==\"$DOCKERHUB_NAME\" and .commit==\"$GIT_COMMIT\" ).state" | head -n 1 )
 	 else
	    build_status=$( echo $buildhistory | jq  -r ".objects[] | select(.build_tag==\"$DOCKERHUB_NAME\").state" | head -n 1 )
         fi
		
        if [[ ! $build_status == "Pending" ]] && [[ ! $build_status == "In progress" ]] && [[ ! $build_status == "Success" ]] && [ $wait_in_case_of_error -gt 0 ]; then
		echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME failed on DockerHub ( status $build_status), will wait $wait_in_case_of_error in case it will be ok"
         wait_in_case_of_error=$(( $wait_in_case_of_error - 1 ))
        fi

        if [[ ! $build_status == "Pending" ]] && [[ ! $build_status == "In progress" ]] && [[ ! $build_status == "Success" ]] && [ $wait_in_case_of_error -eq 0 ]; then
         echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME failed on DockerHub( status $build_status), please check it!!!"
         exit 1
        fi
        if [[ $build_status == "Success" ]]; then
         echo "Build  $DOCKERHUB_REPO:$DOCKERHUB_NAME done successfully on DockerHub"
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



