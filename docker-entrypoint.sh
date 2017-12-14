#!/bin/bash

set -e

CMD="$1"

if [ -z "$GIT_SRC" ]; then
echo "GIT source not given"
exit 1
fi

if [ -z "$GIT_NAME" ]; then
echo "GIT repo name not given"
exit 1
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
	if [ $(echo $files_changed | grep $GIT_VERSIONFILE | wc -l) -eq 0 ]; then                        
	     echo "Pipeline aborted due to no version file changed"
             exit 1
        fi
	git checkout $GIT_BRANCH
        version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "Version is $version"
        if [ $(git tag | grep -E "^$version$" | wc -l) -ne 0 ]; then                        
         echo "Pipeline aborted due to version already present in tags"
         exit 1
        fi
        
        if [[ ! $version  =~ ^[0-9]+\.[0-9]+$ ]] ; then 
         echo "Version ${version} does not respect format: \"number.number\", please change it"
         exit 1
        fi
				      
	git fetch --tags
        latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
        check_version_bigger=$(echo $version"."$latestTag | awk -F. '{if ($1 > $3 || ( $1 == $3 && $2 > $4) ) print "OK"}')
        
        if [[ ! $check_version_bigger == "OK" ]]; then 
         echo "Pipeline aborted due to version ${version} being smaller than last version ${last_version}"
	 exit 1
        fi             
 fi
     
if [[ "$GIT_BRANCH" == "master" ]; then     

   export HOME=$(pwd)
   echo "[distutils]\nindex-servers =\n   eea\n\n[eea]\nrepository: http://eggrepo.apps.eea.europa.eu/\nusername: ${EGGREPO_USERNAME}\npassword: ${EGGREPO_PASSWORD}" > .pypirc
   python setup.py register -r eea
   python setup.py sdist upload -r eea

fi

exec "$@"
