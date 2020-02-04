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

GITHUBURL=https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/git

get_catalog_paths()
{

   REPO=$1	
   if [ ! -d "/${RANCHER_CATALOG_GITNAME}" ];then   
         cd /
         git clone https://github.com/${GIT_ORG}/${RANCHER_CATALOG_GITNAME}.git
   fi
    
   cd /${RANCHER_CATALOG_GITNAME}
   RANCHER_CATALOG_PATHS=$(for i in $(grep ${REPO}: */*/*/docker-compose* | awk -F'[ /]' '{print $1"/"$2}' | uniq); do grep -l ${REPO}: $i"/"$(find $i  -maxdepth 1 -type d  | awk  'BEGIN{FS="/"}{print $3}' | sort -n | tail -n 1)/docker-compose*; done | awk -F'/' '{print $1"/"$2}')
   cd /
   
}


git clone $GIT_SRC
cd $GIT_NAME

# Image release on DockerHub
if [[ "$GIT_BRANCH" == "master" ]]; then

    git fetch --tags
   
    latestTag=$(git describe --tags)

    files_changed=$(git --no-pager diff --name-only master $(git merge-base $(git describe --tags)  master) | wc -l )

    if [ $files_changed -eq 0 ]; then
      echo "No files changed since last release, $latestTag"
      echo "Will continue without the release on github"
      version=$latestTag
    else
      echo "-------------------------------------------------------------------------------"
      echo "Found $files_changed files changed since last release ($latestTag)"

      if [ -f "${EXTRACT_VERSION_SH}" ]; then
        echo "Found EXTRACT_VERSION_SH script ( ${EXTRACT_VERSION_SH} ) , will run it to calculate the new version"
        version=$(./${EXTRACT_VERSION_SH})
      else
	echo "Calculating version with $latestTag + 0.1"
        version=$(echo $latestTag + 0.1 | bc)
      fi

      echo "Version is $version"

      
      echo "-------------------------------------------------------------------------------"
      if [ -n "$DEPENDENT_DOCKERFILE_URL" ];then
	      echo "Received DEPENDENT_DOCKERFILE_URL variable - values $DEPENDENT_DOCKERFILE_URL"
	      echo "Checking if there are any local Dockerfiles - ex for devel"
	      tree=""
	      for dependency in "$DEPENDENT_DOCKERFILE_URL"
	      do
	       if [ -f "$dependency" ]; then
		  echo "Found local dependency - $dependency, will continue with the update on it"
                   
		  sed -i "s/^FROM $DOCKERHUB_REPO.*/FROM $DOCKERHUB_REPO:$version/" $dependency
                    

                  valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat $dependency | base64))\",\"encoding\": \"base64\" }" sha
                  sha_dockerfile=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
		  
		  echo "Created blob for Dockerfile -- $sha_dockerfile"
		  if [ -n "$tree" ]; then
			  tree=","$tree
		  fi
		  tree="{\"path\": \"$dependency\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_dockerfile}\" }$tree"
         	fi
                
	      done    

            if [ -n "$tree" ]; then
                echo "Using tree [$tree]"
	        valid_curl_get_result ${GITHUBURL}/refs/heads/master sha
                sha_master=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['object']['sha']")
                echo "Sha for master is $sha_master"

                valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [$tree]}" sha
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

               echo "Dependent Dockerfile(s) commited successfully to master with new version"
 
           else
   	        echo "Did not find any local dependent Dockerfiles, will not do any commits to repo"
           fi
      fi
			

              

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

    /dockerhub_release_wait.sh ${DOCKERHUB_REPO} $version $TRIGGER_MAIN_URL


    echo "-------------------------------------------------------------------------------"
    echo "Starting the Rancher catalog release"
    
    if [ -z "$RANCHER_CATALOG_PATHS" ]; then
    
	  get_catalog_paths $DOCKERHUB_REPO
       
    fi
    
    for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
      	/add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH $DOCKERHUB_REPO $version $RANCHER_CATALOG_SAME_VERSION 
    done

   
      echo "-------------------------------------------------------------------------------"
      if [ -n "$DEPENDENT_DOCKERFILE_URL" ];then
              echo "Received DEPENDENT_DOCKERFILE_URL variable - values $DEPENDENT_DOCKERFILE_URL"
	      echo "Checking if there are any remote(other repos, other branches) Dockerfiles"
              
	      for dependency in "$DEPENDENT_DOCKERFILE_URL"
              do
		if [ -f "$dependency" ] || [ "${#DEP[@]}" -lt 5 ]; then 
			continue
		fi	
                IFS='/' read -ra DEP <<< "$dependency"
                 
		PATH=$(echo $dependency | sed 's#^[^/]*/[^/]*/blob/[^/]*/\(.*\)$#\1#')

                echo "Found dependency - Organization:${DEP[0]}, Repository:${DEP[1]}, Branch:${DEP[3]}, PATH:$PATH"

                GITHUBURL=https://api.github.com/repos/${DEP[0]}/${DEP[1]}

		curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "${GITHUBURL}/contents/${PATH}?ref=${DEP[3]}"  > /tmp/Dockerfile

		if [ $(grep -c "^FROM ${DOCKERHUB_REPO}" /tmp/Dockerfile) -eq 0 ]; then
                     echo "There was a problem getting the Dockerfile or it does not contain a ${DOCKERHUB_REPO} reference"
                     cat /tmp/Dockerfile
		     exit 1
	        fi
 
                if [ $(grep -c "^FROM ${DOCKERHUB_REPO}:$version$" /tmp/Dockerfile) -eq 1 ]; then
                 echo "Dockerfile already updated, skipping"
                 continue
                fi

                old_version=$( grep  "^FROM ${DOCKERHUB_REPO}" /tmp/Dockerfile  | awk -F':| ' '{print $3}')
                
		biggest_version=$(echo "$version
$old_version" | sort  --sort=version | tail -n 1)

                if [[ "$old_version" == "$version" ]]; then
                   echo "${version} is smaller than the version from Dockerfile - ${old_version}, skipping"
                   continue
	        fi


		echo "Updating Dockerfile with the released version"

                valid_curl_get_result "$GITHUBURL/contents/${PATH}?ref=${DEP[3]}" sha

                sha_versionfile=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

                sed -i "s/^FROM ${DOCKERHUB_REPO}.*/FROM ${DOCKERHUB_REPO}:$version/g" /tmp/Dockerfile

                valid_curl_put_result "$GITHUBURL/contents/${PATH}" "{\"message\": \"Release ${DOCKERHUB_REPO} $version\", \"sha\": \"${sha_versionfile}\", \"branch\": \"${DEP[3]}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat versions.cfg | base64))\"}"

                echo "${DEP[0]}/${DEP[1]},branch ${DEP[3]},$PATH updated succesfully"

             done
          
       fi

    if [ -z "$TRIGGER_RELEASE" ];then
	    echo "-------------------------------------------------------------------------------"
            echo "Did not receive a trigger to a devel repo"
	    exit 0
    fi

    echo "-------------------------------------------------------------------------------"
    echo "Starting triggered release(s)"

    for trigger in "$TRIGGER_RELEASE"
    do
        IFS=';' read -ra TRIG <<< "$trigger"

         echo "Found release on ${DEP[0]}, will trigger it with the new version - $version"

         curl -i -H "Content-Type: application/json" --data "{\"source_type\": \"Tag\", \"source_name\": \"$version\"}" -X POST https://hub.docker.com/api/build/v1/source/${DEP[1]}
	 
	 /dockerhub_release_wait.sh ${DEP[0]} $version ${DEP[1]}


         get_catalog_paths ${DEP[0]}

         for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
               /add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH ${DEP[0]} $version $RANCHER_CATALOG_SAME_VERSION
         done



    done
	    



fi

exec "$@"
