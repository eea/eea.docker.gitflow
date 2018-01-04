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

     if [ -z "$version" ]; then
      echo "Version not calculated!"
      exit 1
     fi


     echo "-------------------------------------------------------------------------------"
     echo "Update devel Dockerfile"

     githubApiUrl="https://api.github.com/repos/${GIT_ORG}/${WWW_GITNAME}/contents/devel/Dockerfile"
     curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" $githubApiUrl  > Dockerfile

     if [ $(grep -c "FROM " Dockerfile) -eq 0 ]; then
       echo "There was a problem getting the WWW Devel Dockerfile"
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


      DOCKERHUB_WWWREPO_ESC=$(echo $DOCKERHUB_WWWREPO | sed 's/\//\\\//g')
      sed -i "s/^FROM $DOCKERHUB_WWWREPO_ESC.*/FROM $DOCKERHUB_WWWREPO_ESC:$version/" Dockerfile

      result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_file}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat Dockerfile | base64))\"}" $githubApiUrl)

         if [ $(echo $result | grep -c "HTTP/1.1 200 OK") -eq 1 ]; then
            echo "WWW Dockerfile updated succesfully"
         else
            echo "There was an error updating the WWW Dockerfile, please check the execution"
            echo $result
            exit 1
         fi





     echo "-------------------------------------------------------------------------------"

     echo "Starting the release $version"
     curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

     if [ $( echo $curl_result | grep -c  "HTTP/1.1 201 Created" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
     fi
     echo "-------------------------------------------------------------------------------"

     /dockerhub_release_wait.sh ${DOCKERHUB_WWWREPO} $version


     echo "-------------------------------------------------------------------------------"
     echo "Starting the Rancher catalog release"

     export RANCHER_CATALOG_PATH=templates/www-plone
     export DOCKER_IMAGENAME=$DOCKERHUB_WWWREPO
     export DOCKER_IMAGEVERSION=$version
     /add_rancher_catalog_entry.sh


     echo "-------------------------------------------------------------------------------"
     echo "Starting the www-develop release on dockerhub"

     curl -H "Content-Type: application/json" --data "{\"source_type\": \"Tag\", \"source_name\": \"$version\"}" -X POST https://registry.hub.docker.com/u/$DOCKERHUB_WWWDEVREPO/trigger/$TRIGGER_URL/
     
     /dockerhub_release_wait.sh ${DOCKERHUB_WWWDEVREPO} $version

     echo "-------------------------------------------------------------------------------"
     export RANCHER_CATALOG_PATH=templates/www-eea
     export DOCKER_IMAGENAME=$DOCKERHUB_WWWDEVREPO
     export DOCKER_IMAGEVERSION=$version
     /add_rancher_catalog_entry.sh



fi

exec "$@"






