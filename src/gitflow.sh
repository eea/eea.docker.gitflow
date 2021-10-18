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
if [[ "$GIT_BRANCH" == "master" ]] || [[ "$GITFLOW_BEHAVIOR" == "RUN_ON_TAG" ]]; then

  if [[ "$GITFLOW_BEHAVIOR" == "RUN_ON_TAG" ]]; then
    version=$GIT_BRANCH
    echo "Script is running on tag, so it will skip the release part"
    echo "Version is $version"
    git checkout $version
  else    
    git fetch --tags
   
    latestTag1=$(git describe --tags --abbrev=0)
    #check in case there are multiple tags per commit
    latestTag1=$(git log  --tags --decorate=full | grep refs/tags/$latestTag1 | grep -o refs/tags/[^\ ,\)]*  | sed 's#refs/tags/##g' | sort --sort=version | tail -n 1)

    latestTag2=$(git for-each-ref --sort=-taggerdate --count=1 --format '%(refname:short)' refs/tags)

    latestTag=$(echo "$latestTag1
$latestTag2" | sort --sort=version | tail -n 1)

    files_changed=$(git --no-pager diff --name-only master $(git merge-base $latestTag  master) | wc -l )

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
	
	echo "Calculating version using YEAR.MONTH.DAY-version format"

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


      fi

      echo "Version is $version"

      
      echo "-------------------------------------------------------------------------------"
      if [ -n "$DEPENDENT_DOCKERFILE_URL" ];then
	      echo "Received DEPENDENT_DOCKERFILE_URL variable - values $DEPENDENT_DOCKERFILE_URL"
	      echo "Checking if there are any local Dockerfiles - ex for devel"
	      tree=""
	      for dependency in $DEPENDENT_DOCKERFILE_URL
	      do
	       if [ -f "$dependency" ]; then
		  echo "Found local dependency - $dependency, will continue with the update on it"
                   
		  sed -i "s#^FROM $DOCKERHUB_REPO.*#FROM $DOCKERHUB_REPO\:$version#g" $dependency
                    

                  valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat $dependency | base64))\",\"encoding\": \"base64\" }" sha
                  sha_dockerfile=$(echo $curl_result |  jq -r '.sha // empty')
		  
		  echo "Created blob for Dockerfile -- $sha_dockerfile"
		  if [ -n "$tree" ]; then
			  tree=","$tree
		  fi
		  tree="{\"path\": \"$dependency\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_dockerfile}\" }$tree"
         	fi
                
	      done    

            if [ -n "$tree" ]; then
                echo "Using tree [$tree]"
	        valid_curl_get_result ${GITHUBURL}/refs/heads/master object.sha
                sha_master=$(echo $curl_result |  jq -r '.object.sha // empty'
                echo "Sha for master is $sha_master"

                valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [$tree]}" sha
                sha_newtree=$(echo $curl_result |  jq -r '.sha // empty')
                echo "Created a github tree - $sha_newtree"

                valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Release $version\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha
                sha_new_commit=$(echo $curl_result |  jq -r '.sha // empty')
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
      curl_result=$( curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\nChanges since last release: https://github.com/${GIT_ORG}/${GIT_NAME}/compare/$latestTag...$version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

      if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
        echo "There was a problem with the release"
        echo "https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases"
	echo "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"
	echo $curl_result
        exit 1
      fi
    fi

    fi
   

    echo "-------------------------------------------------------------------------------"

    /dockerhub_release_wait.sh ${DOCKERHUB_REPO} $version $TRIGGER_MAIN_URL


    echo "-------------------------------------------------------------------------------"
    if [[ "$GITFLOW_BEHAVIOR" == "TAG_ONLY" ]]; then
         echo "Received TAG_ONLY as gitflow behavior, so will skip the catalog release"
        
    else


      echo "Starting the Rancher catalog release"
    
      if [ -z "$RANCHER_CATALOG_PATHS" ]; then
    
  	  get_catalog_paths $DOCKERHUB_REPO
       
      fi
    
      for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
        	/add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH $DOCKERHUB_REPO $version $RANCHER_CATALOG_SAME_VERSION 
      done

    fi


      echo "-------------------------------------------------------------------------------"
      if [ -n "$DEPENDENT_DOCKERFILE_URL" ];then
              echo "Received DEPENDENT_DOCKERFILE_URL variable - values $DEPENDENT_DOCKERFILE_URL"
	      echo "Checking if there are any remote(other repos, other branches) Dockerfiles"
              
	      for dependency in $DEPENDENT_DOCKERFILE_URL
              do
		IFS='/' read -ra DEP <<< "$dependency"
		if [ -f "$dependency" ] || [ "${#DEP[@]}" -lt 5 ]; then 
			continue
		fi	
                 
		DOCKERFILE_PATH=$(echo $dependency | sed 's#^[^/]*/[^/]*/blob/[^/]*/\(.*\)$#\1#')

                echo "Found dependency - Organization:${DEP[0]}, Repository:${DEP[1]}, Branch:${DEP[3]}, Dockerfile path:$DOCKERFILE_PATH"

                GITHUBURL=https://api.github.com/repos/${DEP[0]}/${DEP[1]}

		DEPENDENT_DOCKERFILE_TIMEOUT=${DEPENDENT_DOCKERFILE_TIMEOUT:-60}
		DOCKERFILE_RETRY=${DEPENDENT_DOCKERFILE_RETRY:-10}

		while [ $DOCKERFILE_RETRY -gt 0 ]
		do

	 		curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "${GITHUBURL}/contents/${DOCKERFILE_PATH}?ref=${DEP[3]}"  > /tmp/Dockerfile

			if [ $(grep -c "^FROM ${DOCKERHUB_REPO}" /tmp/Dockerfile) -eq 0 ]; then
              	             echo "There was a problem getting the Dockerfile or it does not contain a ${DOCKERHUB_REPO} reference"
                	     cat /tmp/Dockerfile
	         	     exit 1
	                fi
 
	  		if [[ "$GITFLOW_BEHAVIOR" == "TAG_ONLY" ]]; then
                		if [ $(grep -c "^FROM ${DOCKERHUB_REPO}:$version$" /tmp/Dockerfile) -eq 1 ]; then
                		       echo "Dependent dockerfile is already updated to $version"
				       DOCKERFILE_RETRY=-100
	      			else
 		   		    echo "Dependent dockerfile is not yet updated to $version, waiting $DEPENDENT_DOCKERFILE_TIMEOUT seconds"
		 		    sleep $DEPENDENT_DOCKERFILE_TIMEOUT
				    let DOCKERFILE_RETRY=$DEPENDENT_DOCKERFILE_RETRY-1
	                        fi

                        else
                              if [ $(grep -c "^FROM ${DOCKERHUB_REPO}:$version$" /tmp/Dockerfile) -eq 1 ]; then
                                     echo "Dockerfile already updated, skipping"
                                     DOCKERFILE_RETRY=-100
			      else
	              	          echo "Dockerfile not yet updated"
				  DOCKERFILE_RETRY=-5
			      fi
                       fi
                done
             
		if [ $DOCKERFILE_RETRY -eq -100 ]; then
			continue
	        fi

		if [ $DOCKERFILE_RETRY -eq 0 ]; then
			echo "Dependent dockerfile was not updated in $DEPENDENT_DOCKERFILE_RETRY x $DEPENDENT_DOCKERFILE_TIMEOUT seconds, exiting with error ( TAG_ONLY behavior) "
			exit 1
		fi


                old_version=$( grep  "^FROM ${DOCKERHUB_REPO}" /tmp/Dockerfile  | awk -F':| ' '{print $3}')
                
	        echo "Dockerfile current version is - $old_version"	
		if [[ "$old_version" == "latest" ]]; then 
		   old_version="0.0"
		fi
		biggest_version=$(echo "$version
$old_version" | sort  --sort=version | tail -n 1)

                if [[ "$old_version" == "$biggest_version" ]]; then
                   echo "${version} is smaller or equal than the version from Dockerfile, skipping"
                   continue
	        fi
                 


		echo "Updating Dockerfile with the released version"

                valid_curl_get_result "$GITHUBURL/contents/${DOCKERFILE_PATH}?ref=${DEP[3]}" sha

                sha_dockerfile=$(echo $curl_result |  jq -r '.sha // empty')

                sed -i "s#^FROM ${DOCKERHUB_REPO}.*#FROM ${DOCKERHUB_REPO}\:$version#g" /tmp/Dockerfile

                valid_curl_put_result "$GITHUBURL/contents/${DOCKERFILE_PATH}" "{\"message\": \"Release ${DOCKERHUB_REPO} $version\", \"sha\": \"${sha_dockerfile}\", \"branch\": \"${DEP[3]}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat /tmp/Dockerfile | base64))\"}"

                echo "${DEP[0]}/${DEP[1]},branch ${DEP[3]},$DOCKERFILE_PATH updated succesfully"

             done
          
       fi

    if [ -z "$TRIGGER_RELEASE" ];then
	    echo "-------------------------------------------------------------------------------"
            echo "Did not receive a post-processing trigger to a dockerhub repo"
	    exit 0
    fi

    if [[ "$GITFLOW_BEHAVIOR" == "TAG_ONLY" ]]; then
	    echo "Skipping triggered release(s) because of the TAG_ONLY parameter"
	    exit 0
    fi

    echo "-------------------------------------------------------------------------------"
    echo "Starting triggered release(s)"


    for trigger in $TRIGGER_RELEASE
    do
        IFS=';' read -ra TRIG <<< "$trigger"

         echo "Found release on ${TRIG[0]}, will trigger it with the new version - $version"

	 
	 /dockerhub_release_wait.sh ${TRIG[0]} $version ${TRIG[1]}


         get_catalog_paths ${TRIG[0]}

         for RANCHER_CATALOG_PATH in ${RANCHER_CATALOG_PATHS}; do
               /add_rancher_catalog_entry.sh $RANCHER_CATALOG_PATH ${TRIG[0]} $version $RANCHER_CATALOG_SAME_VERSION
         done

         #make sure master is resubmitted if failed
	 get_dockerhub_buildhistory ${TRIG[0]}
         build_status=$( echo $buildhistory | python -c "import sys, json
try:
  data_dict = json.load(sys.stdin)
  build_tag = 'latest'
  for res in data_dict['objects']:
    if res['build_tag'] == build_tag:
      print('%s' % res['state'])
      break
except:
  print('Error parsing DockerHub API response %s' % sys.stdin)
")
        if [[ $build_status == "Failed" ]] ; then
                echo "Build  ${TRIG[0]}:latest failed on DockerHub, will resubmit it"
                curl -i -H "Content-Type: application/json" --data "\"docker_tag\": \"master\"}" -X POST https://hub.docker.com/api/build/v1/source/${TRIG[1]}
        fi

    done
	    
fi

exec "$@"
