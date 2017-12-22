#!/bin/bash

set -e

git clone $GIT_SRC
cd $GIT_NAME

# KGS release
if [[ "$GIT_BRANCH" == "master" ]]; then

       #if there was any changes between master and last tagt fetch origin pull/$GIT_CHANGE_ID/head:$GIT_BRANCH
        files_changed=$(git --no-pager diff --name-only $GIT_BRANCH $(git merge-base $GIT_BRANCH master))
        latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
        files_changed=$(git --no-pager diff --name-only master $(git merge-base $latestTag  master) | wc -l )

      if [ $files_changed -eq 0 ]; then
       echo "No files changed since last release, $latestTag"
       exit 0
      fi
     echo "-------------------------------------------------------------------------------"
     echo "Found $files_changed files changed since last release ($latestTag)"
     version=$(date +"%y.%m.%d")

     if [[ "$latestTag" == "$version"* ]]; then
        version=$(echo $version | awk -F "-" '{print $1"-"($2+1)}')
     fi
  
     echo "New version is $version"
     echo "-------------------------------------------------------------------------------"
     echo "Updating Dockerfile"

     githubApiUrl="https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/contents/Dockerfile"
     curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" $githubApiUrl  > Dockerfile

     if [ $(grep -c "FROM " Dockerfile) -eq 0 ]; then
       echo "There was a problem getting the Dockerfile"
       cat Dockerfile
       exit 1
     fi
     
      curl_result=$( curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" $githubApiUrl )
      if [ $( echo $curl_result | grep -c '"sha"' ) -eq 0 ]; then
          echo "There was a problem with the GitHub API request:"
          echo $curl_result
          exit 1
      fi

      sha_file=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

      sed -i "s/^    EEA_KGS_VERSION=.*/    EEA_KGS_VERSION=$version/" Dockerfile

      result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_file}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat Dockerfile | base64))\"}" $githubApiUrl)

         if [ $(echo $result | grep -c "HTTP/1.1 200 OK") -eq 1 ]; then
            echo "Dockerfile updated succesfully"
         else
            echo "There was an error updating the Dockerfile, please check the execution"
            echo $result
            exit 1
         fi
     echo "-------------------------------------------------------------------------------"
     echo "Extracting changelog"
     change_log=$(/unifyChangelogs.py $latestTag master json 2> /dev/null)
     echo "-------------------------------------------------------------------------------"

     echo "Starting the release $version"
     curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  $change_log, \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

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
        FOUND_BUILD=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/?page_size=100 | grep -c "\"dockertag_name\": \"$version\"")
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

        build_status=$(curl -s https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/buildhistory/?page_size=100 | python -c "import sys, json
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



fi

exec "$@"






