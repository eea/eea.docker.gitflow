#!/bin/bash

set -e

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi


git clone $GIT_SRC
cd $GIT_NAME



# KGS release
if [[ "$GIT_BRANCH" == "master" ]]; then

        latestTag=$(git describe --abbrev=0 --tags)
        files_changed=$(git --no-pager diff --name-only master $(git merge-base $latestTag  master) | wc -l )

      if [ $files_changed -eq 0 ]; then
       echo "No files changed since last release, $latestTag"
       exit 0
      fi
     echo "-------------------------------------------------------------------------------"
     echo "Found $files_changed files changed since last release ($latestTag)"
     version=$(date +"%-y.%-m.%-d")

     echo "Version is $version"

     if [[ "$latestTag" == "$version"* ]]; then
        if [ ! -z "$HOTFIX" ]; then
           echo "HOTFIX parameter received, calculating new version"
           version=$(echo $latestTag | awk -F "-" '{print $1"-"($2+1)}')
            echo "New version is $version"
       else
           echo "Version $version already released, run with HOTFIX parameter to re-release."
           exit 0
        fi
     fi
  
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

      sha_file=$(echo $curl_result |  jq -r '.sha // empty')

      sed -i "s/^    EEA_KGS_VERSION=.*/    EEA_KGS_VERSION=$version/" Dockerfile

      result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_file}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat Dockerfile | base64))\"}" $githubApiUrl)

         if [ $(echo $result | grep -cE "HTTP/[0-9\.]* 200") -eq 1 ]; then
            echo "Dockerfile updated successfully"
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

     if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
     fi
     echo "-------------------------------------------------------------------------------"
   
     /dockerhub_release_wait.sh ${DOCKERHUB_KGSREPO} $version
     
     echo "-------------------------------------------------------------------------------"
     echo "Starting the kgs-devel release on dockerhub"

     echo "curl -H \"Content-Type: application/json\"  --data  \"{\"source_type\": \"Tag\", \"source_name\": \"$version\"}\" -X POST https://hub.docker.com/api/build/v1/source/$TRIGGER_URL"

     curl -i -H "Content-Type: application/json" --data "{\"source_type\": \"Tag\", \"source_name\": \"$version\"}" -X POST https://hub.docker.com/api/build/v1/source/$TRIGGER_URL


     echo "-------------------------------------------------------------------------------"
     TIME_TO_WAIT_START=60
     echo "Wait $TIME_TO_WAIT_START *10 seconds for the build $DOCKERHUB_KGSDEVREPO:$version to be started on DockerHub"

     while [ $TIME_TO_WAIT_START  -ge 0 ]; do
        sleep 10
        TIME_TO_WAIT_START=$(( $TIME_TO_WAIT_START - 1 ))
	get_dockerhub_buildhistory ${DOCKERHUB_KGSDEVREPO}

	FOUND_BUILD=$( echo $buildhistory |  grep -E "\{.*\"build_tag\": \"$version\",[^\{]*\"state\": \"(Pending|In progress)\".*\}"  | wc -l )
	

        if [ $FOUND_BUILD -gt 0 ];then
          echo "DockerHub started the $DOCKERHUB_KGSDEVREPO:$version release"
          break
        fi
        if [ ! -z "$TRIGGER_URL" ] && ! (( TIME_TO_WAIT_START % 10 )); then
            echo "One minute passed, build not starting , will use trigger to re-start build"
            curl -i -H "Content-Type: application/json" --data "{\"source_type\": \"Tag\", \"source_name\": \"$version\"}" -X POST https://hub.docker.com/api/build/v1/source/$TRIGGER_URL
        fi
    done




fi

exec "$@"






