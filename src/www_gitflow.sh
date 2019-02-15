#!/bin/bash

set -e

DOCKERHUB_KGSREPO_ESC=$(echo $DOCKERHUB_KGSREPO | sed 's/\//\\\//g')
DOCKERHUB_WWWREPO_ESC=$(echo $DOCKERHUB_WWWREPO | sed 's/\//\\\//g')

source /common_functions


git clone $GIT_SRC
cd $GIT_NAME


# WWW release
if [[ "$GIT_BRANCH" == "master" ]]; then
       
      skip_release=0
      valid_curl_get_result https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/releases/latest tag_name
      version=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['tag_name']")
  
      echo "Found KGS latest release - $version"
      
      if [ $(git tag | grep -c "^$version$" ) -ne 0 ]; then
         if [ ! -z "$HOTFIX" ];then
            echo "HOTFIX parameter received, will generate new version for WWW"
            version=$(echo $version | awk -F "-" '{print $1"-"($2+1)}')
         else
             echo "Version $version already released, skipping"
             echo "Run with HOTFIX parameter to generate new version"
             skip_release=1
         fi
      fi
     
     if [ $skip_release -eq 0 ]; then
      echo "New version is $version"

      if [ -z "$version" ]; then
        echo "Version not calculated!"
        exit 1
      fi


      echo "-------------------------------------------------------------------------------"
      echo "Updating Dockerfiles for WWW and WWW-devel"

      sed -i "s/^FROM $DOCKERHUB_KGSREPO_ESC.*/FROM $DOCKERHUB_KGSREPO_ESC:$version/" Dockerfile
      sed -i "s/^FROM $DOCKERHUB_WWWREPO_ESC.*/FROM $DOCKERHUB_WWWREPO_ESC:$version/" devel/Dockerfile

      GITHUBURL=https://api.github.com/repos/${GIT_ORG}/${WWW_GITNAME}/git

      valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat Dockerfile | base64))\",\"encoding\": \"base64\" }" sha
      sha_dockerfile=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
      echo "Created blob for Dockerfile -- $sha_dockerfile"
      valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat devel/Dockerfile | base64))\",\"encoding\": \"base64\" }" sha
      sha_devdockerfile=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
      echo "Created blob for devel/Dockerfile -- $sha_devdockerfile"

     

      valid_curl_get_result ${GITHUBURL}/refs/heads/master sha
      sha_master=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['object']['sha']")
      echo "Sha for master is $sha_master"


      valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [{\"path\": \"Dockerfile\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_dockerfile}\" }, { \"path\": \"devel/Dockerfile\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_devdockerfile}\" }]}" sha
      sha_newtree=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
   
      echo "Created a github tree - $sha_newtree"
     
      valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Release $version\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha
      sha_new_commit=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
     
      echo "Added a new commit - $sha_new_commit"

     
      # update master to commit
      curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/master)

      if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 200" ) -eq 0 ]; then
            echo "There was a problem with the Dockerfile and devel/Dockerfile commit"
            echo $curl_result
            exit 1
      fi

      echo "Dockerfiles commited successfully to master"    


      echo "-------------------------------------------------------------------------------"

      echo "Starting the release $version"
     
      curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

      if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
      fi
     fi #finished skip_release
     
    
     echo "-------------------------------------------------------------------------------"
  

     if [ $( curl  -s  -u $DOCKERHUB_USER:$DOCKERHUB_PASS  "https://cloud.docker.com/api/audit/v1/action/?include_related=true&limit=10&object=/api/repo/v1/repository/${DOCKERHUB_WWWREPO}/" |  grep -E "\{.*\"build_tag\": \"$version\",[^\{]*\"state\": \"Success\".*\}"  | wc -l  ) -gt 0 ]; then
       echo "Found successfull release on DOCKERHUB - ${DOCKERHUB_WWWREPO}:$version" 
     else 
      /dockerhub_release_wait.sh ${DOCKERHUB_WWWREPO} $version $TRIGGER_MAIN_URL
     fi

     echo "-------------------------------------------------------------------------------"
     echo "Starting the Rancher catalog release"

     export RANCHER_CATALOG_PATH=templates/www-plone
     export DOCKER_IMAGENAME=$DOCKERHUB_WWWREPO
     export DOCKER_IMAGEVERSION=$version
     /add_rancher_catalog_entry.sh


     echo "-------------------------------------------------------------------------------"
     
     i if [ $( curl  -s  -u $DOCKERHUB_USER:$DOCKERHUB_PASS  "https://cloud.docker.com/api/audit/v1/action/?include_related=true&limit=10&object=/api/repo/v1/repository/${DOCKERHUB_WWWDEVREPO}/" |  grep -E "\{.*\"build_tag\": \"$version\",[^\{]*\"state\": \"Success\".*\}"  | wc -l  ) -gt 0 ]; then
       echo "Found successfull release on DOCKERHUB - ${DOCKERHUB_WWWDEVREPO}:$version"
     else
       /dockerhub_release_wait.sh ${DOCKERHUB_WWWDEVREPO} $version $TRIGGER_URL
     fi

     echo "-------------------------------------------------------------------------------"
     export RANCHER_CATALOG_PATH=templates/www-eea
     export DOCKER_IMAGENAME=$DOCKERHUB_WWWDEVREPO
     export DOCKER_IMAGEVERSION=$version
     /add_rancher_catalog_entry.sh



fi

exec "$@"






