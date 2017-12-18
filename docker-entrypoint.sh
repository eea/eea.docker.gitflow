#!/bin/bash

set -e

CMD="$1"

if [ -z "$GIT_ORG" ]; then
 echo "GIT organization not given"
 exit 1
fi

if [ -z "$GIT_NAME" ]; then
 echo "GIT repo name not given"
 exit 1
fi

GIT_SRC=https://github.com/${GIT_ORG}/${GIT_NAME}.git

if [ -z "$GIT_USERNAME" ]; then
 GIT_USERNAME="EEA Jenkins"
fi

if [ -z "$GIT_EMAIL" ]; then
 GIT_EMAIL="eea-github@googlegroups.com"
fi

if [ -z "$GIT_USERNAME" ]; then
 GIT_USERNAME="EEA Jenkins"
fi

if [ -z "$GIT_EMAIL" ]; then
 GIT_EMAIL="eea-github@googlegroups.com"
fi

if [ -z "$EGGREPO_URL" ]; then
 EGGREPO_URL=https://eggrepo.eea.europa.eu/
fi


if [ -z "$KGS_GITNAME" ]; then
  KGS_GITNAME=eea.docker.kgs
fi

if [ -z "KGS_VERSIONS_PATH" ]; then
  KGS_VERSIONS_PATH=src/plone/versions.cfg
fi

git clone $GIT_SRC
cd $GIT_NAME
	
if [ ! -z "$GIT_CHANGE_ID" ]; then


        git fetch origin pull/$GIT_CHANGE_ID/head:$GIT_BRANCH
        files_changed=$(git --no-pager diff --name-only $GIT_BRANCH $(git merge-base $GIT_BRANCH master))

        if [ $(echo $files_changed | grep $GIT_HISTORYFILE | wc -l) -eq 0 ]; then                        
	     echo "Pipeline aborted due to no history file changed"
             exit 1
        fi
        echo "Passed check: History file updated"
    
	if [ $(echo $files_changed | grep $GIT_VERSIONFILE | wc -l) -eq 0 ]; then                        
	     echo "Pipeline aborted due to no version file changed"
             exit 1
        fi
        echo "Passed check: Version file updated"
        
	git checkout $GIT_BRANCH
        version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "Version is $version"
        
        if [ $(git tag | grep -c "^$version$" ) -ne 0 ]; then                        
         echo "Pipeline aborted due to version already present in tags"
         exit 1
        fi
        echo "Passed check: Version is not present in git tags"
        
        if [[ ! $version  =~ ^[0-9]+\.[0-9]+$ ]] ; then 
         echo "Version ${version} does not respect format: \"number.number\", please change it"
         exit 1
        fi
        echo "Passed check: Version format is number.number"
        
				      
	git fetch --tags
        if [ $(git tag | wc -l) -eq 0 ]; then
             echo "Passed check: New version is bigger than last released version (no versions released yet)"
        else
        	latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
        	check_version_bigger=$(echo $version"."$latestTag | awk -F. '{if ($1 > $3 || ( $1 == $3 && $2 > $4) ) print "OK"}')
        
        	if [[ ! $check_version_bigger == "OK" ]]; then 
        	 echo "Pipeline aborted due to version ${version} being smaller than last version ${last_version}"
		 exit 1
        	fi             
        	echo "Passed check: New version is bigger than last released version"
        fi
        echo "Passed all checks"
fi
     
if [[ "$GIT_BRANCH" == "master" ]]; then     

        #check if release already exists
	version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "Checking if version is released on EGGREPO"
	http_code=$(curl -s -o /dev/null -I -w  "%{http_code}" "${EGGREPO_URL}d/${GIT_NAME}/f/${GIT_NAME}-${version}.tar.gz")

	if [ $http_code -ne 200 ]; then
         echo "Starting the release ${GIT_NAME}-${version}.tar.gz on repo"
	 export HOME=$(pwd)
   	 echo "[distutils]
index-servers =
   eea

[eea]
repository: $EGGREPO_URL
username: ${EGGREPO_USERNAME}
password: ${EGGREPO_PASSWORD}" > .pypirc

   	 python setup.py register -r eea
   	 python setup.py sdist upload -r eea

	else
	 echo "Release ${GIT_NAME}-${version}.tar.gz already exists on repo, skipping"
	fi

	#check if tag exiss
	if [ $(git tag | grep -c "^$version$") -eq 0 ]; then
	 echo "Starting the creation of the tag $version on master"   

	 export PYTHONIOENCODING=utf8
	 sha_commit=$(curl -s -H "Authorization: bearer $GIT_TOKEN" https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/git/refs/heads/master |  python -c "import sys, json; print json.load(sys.stdin)['object']['sha']")
	 echo "Got master sha: $sha_commit"

	 sha_tag=$(curl -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{ \"tag\": \"$version\", \"message\": \"Release $version\",\"object\": \"${sha_commit}\", \"type\": \"commit\", \"tagger\":{\"name\": \"${GIT_USERNAME}\",\"email\": \"${GIT_EMAIL}\"}}"  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/git/tags |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
	 echo "Created tag with sha: $sha_tag"

	 curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{ \"ref\": \"refs/tags/$version\",  \"sha\": \"${sha_tag}\"}"  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/git/refs 

	 git fetch --tags

	 if [ $(git tag | grep -c "^$version$") -eq 0 ]; then
	   echo "Tag $version not created, exiting with error"
	   exit 1
	 else
	   echo "Tag $version succesfully created"
	 fi

	else
	  echo "Tag $version already created, skipping"
	fi

 # Updating versions.cfg	

 curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}"  > versions.cfg
 
 if [ $(grep -c "^${GIT_NAME} = $version$" versions.cfg) -eq 1 ]; then
 	 echo "KGS versions file already updated, skipping"
 else
       old_version=$( grep  "^${GIT_NAME} =" versions.cfg | awk '{print $3}')
      
       check_version_bigger=$(echo $version"."$old_version | awk -F. '{if ($1 > $3 || ( $1 == $3 && $2 > $4) ) print "OK"}')

       if [[ ! $check_version_bigger == "OK" ]]; then
         echo "${version} is smaller than the version from ${KGS_GITNAME} - ${old_version}, skipping"
       else 

 	 echo "Starting the update of KGS versions file with released version"

         export PYTHONIOENCODING=utf8
         sha_versionfile=$(curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}"  |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
  	 grep -q "^${GIT_NAME} =" versions.cfg  && sed -i "s/^${GIT_NAME} =.*/${GIT_NAME} = $version/" versions.cfg || sed -i "/# automatically set /a ${GIT_NAME} = $version" versions.cfg

  	 result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_versionfile}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat versions.cfg | base64))\"}" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}")
      
         if [ $(echo $result | grep -c "HTTP/1.1 200 OK") -eq 1 ]; then
            echo "KGS versions file updated succesfully"
         else
            echo "There was an error updating the KGS file, please check the execution"
            exit 1
         fi 
      fi
fi

fi

exec "$@"
