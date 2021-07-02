#!/bin/bash

set -e

echo "Starting javascript release script"

if [[ $GIT_NAME == "volto-addon-template" ]]; then
    echo "No release flow for templates, skipping all steps"
    exit 0
fi    
    
if [ -z "$GIT_NAME" ] || [ -z "$GIT_BRANCH" ]; then
 echo "GIT repo name and branch not given"
 exit 1
fi

if [ -z "$GIT_TOKEN" ]; then
 echo "GIT token not given"
 exit 1
fi


GIT_ORG=${GIT_ORG:-'eea'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}
export GITHUB_TOKEN="${GIT_TOKEN}"

GIT_SRC=https://$GIT_USER:$GIT_TOKEN@github.com/${GIT_ORG}/${GIT_NAME}.git



update_package_json()
{
       if [[ ! $2 == "package.json" ]]; then 
               echo "Dependency found in file $2, not package.json, skipping updaate"
	       return
       fi
       echo "Running update dependency in $2 on gitrepo $1 for package $3 version $4"
       git clone https://$GIT_USER:$GIT_TOKEN@github.com/$1.git frontend
       cd frontend
       old_version=$(cat $2 |  python -c "import sys, json; dependencies=json.load(sys.stdin)['dependencies']; print dependencies.get(\"$3\",\"\") ")
       if [ -z "$old_version" ] || [[ "$old_version" == "None" ]] ; then
       	       echo "Did not find the package in dependecies list, skipping"
	       return
       fi

       echo "Found package version - $old_version"
       if [[ "$old_version" == ^* ]]; then 
	       echo "Package version is not fixed, will skip upgrade"; 
	       return
       fi

       if [ "$4" == "$old_version" ]; then
	     echo "The released $3 version is already updated, finishing"
	     return
       fi

       if [[ "$old_version" == "github:${GIT_ORG}/${GIT_NAME}"* ]] || [[ "$old_version" == "${GIT_ORG}/${GIT_NAME}"* ]]; then
             echo "Found dependency with github repo, will update to npm version"
	     old_version=$(echo $old_version | sed 's/\//\\\//g')
	 else    
	 
            biggest_version=$(echo "$4
$old_version" | sort --sort=version | tail -n 1 )

            if [ "$biggest_version" == "$old_version" ]; then
                 echo "The released $3 version is bigger than the released one, finishing"
                 return
            fi
       fi
       echo "Will now update the version file and yarn.lock"
       
       yarn add -W $3@$4

       #Yarn takes a lot of time, will try pull, if it fails because of conflicts, start over"
       pull_error=$(git pull 2>&1 | grep Aborting | wc -l)
       if [ $pull_error -ne 0 ]; then
          echo "There is a concurrency problem on repo $1, will cleanup and retry again"
          cd ..
          rm -rf frontend
          update_package_json $1 $2 $3 $4
       fi
       git status
       git diff
       git add package.json yarn.lock
       git commit -m "Automated release $3@$4" 
       git push
       cd ..
       rm -rf frontend

}

git config --global user.name "${GIT_USERNAME}"
git config --global user.email "${GITHUB_USER}@users.noreply.github.com"

git clone $GIT_SRC

if [ ! -f $GIT_NAME/package.json ]  || [ -f $GIT_NAME/setup.py ] || [ -f $GIT_NAME/Dockerfile ]; then
   rm -rf $GIT_NAME
   echo "Not a javascript package, the check was wrong"
   /docker-entrypoint.sh $@
   exit 0
fi

cd "$GIT_NAME"


#if PR
if [ -n "$GIT_CHANGE_ID" ] && [[ "$GIT_CHANGE_TARGET" == "master" ]] && [[ "$GIT_CHANGE_BRANCH" == "develop" ]]; then
         
        echo "Starting pre-release on PULL REQUEST"

	git checkout $GIT_CHANGE_BRANCH
	existing_tags=$(git tag)

        if [ -z "$existing_tags" ]; then
             echo "There are no tags, we need to first release initial version"
	     git checkout master
	     version=$(grep '"version"' package.json | awk -F'"' '{print $4}')
	     git tag -a $version -m "Initial release"
	     git push origin tag $version
	     git checkout $GIT_CHANGE_BRANCH     
	fi
        version=$(grep '"version"' package.json | awk -F'"' '{print $4}')
        
	#check if version was already updated
        git fetch --tags

        if [ $(git diff --name-status ${GIT_CHANGE_BRANCH}..${GIT_CHANGE_TARGET} | wc -l) -eq 0 ]; then
		echo "There are no changes to release"
		exit 0
	fi


	if [ $(git tag | grep ^${version}$ | wc -l) -eq 1 ]; then
             echo "Start release with changelog update on new version"
             release-it --config /release-it.json --no-git.tag -i patch --ci
        else
	     echo "Existing version is not yet released, will only auto-update changelog"
             
	     npx_command=$(grep after:bump /release-it.json | awk -F'"' '{print $4}' | awk -F';' '{print $1}' )
	     
	     sh -c "$npx_command"
	     sed -i '/\- Automated release /d' CHANGELOG.md
	     
	     if [ $(git diff CHANGELOG.md | tail -n +5 | grep ^+ | grep -v '\- Automated release' | wc -l ) -gt 0 ]; then
		     # there were other commits besides the automated release ones"
 	             git add CHANGELOG.md
	             git commit -m "Automated release $version"
                     git push
	     else
	             echo "Did not find any new commits beside the automated ones, will not add them"
		     git checkout -- CHANGELOG.md     
	     fi
	fi
        
fi	




if [ -z "$GIT_CHANGE_ID" ] && [[ "$GIT_BRANCH" == "master" ]] ; then

	
	echo "Starting release on github and npm"

        if [ -n "$NPM_TOKEN" ]; then
            echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" > .npmrc
    	else
  	    echo "Did no receive NPM_TOKEN variable, necessary for npm release"
	    exit 1
	fi

        # git checkout $GIT_BRANCH

        if [ -n "$GIT_COMMIT" ]; then
              echo "Received commit as a variable, will checkout on it instead of the $GIT_BRANCH branch"
	      git checkout $GIT_COMMIT
	fi

        version=$(grep '"version"' package.json | awk -F'"' '{print $4}')

        #check if version was already updated
        git fetch --tags
        
        if [ $(git tag | grep ^${version}$ | wc -l) -eq 1 ]; then
             echo "GitHub release already done, skipping tag creation"
        else
	    #echo "Starting GitHub release of version ${version}"
	    #release-it -v
	    
            #sed -i 's/"release": false,/"release": true,/' /release-it.json
            #release-it --no-increment --no-git --github.release --config /release-it.json --ci

	    echo "Create release on $GIT_BRANCH using GitHub API"
	    body=$(npx auto-changelog --stdout --sort-commits date-desc --commit-limit false -u --template https://raw.githubusercontent.com/release-it/release-it/master/templates/changelog-compact.hbs| grep -v '\- Automated release ' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed 's/"/\\\"/g')
	    
	    curl   -X POST   -H "Accept: application/vnd.github.v3+json"  -H "Authorization: bearer $GITHUB_TOKEN"  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases -d "{\"tag_name\": \"$version\",\"name\": \"$version\", \"target_commitish\":\"${GIT_BRANCH}\",  \"body\":  \"$body\"}" 

        fi

	#check if released

	package_name=$(grep '"name"' package.json | awk -F'"' '{print $4}')
        
	if [ $(npm search $package_name --json | grep "\"$package_name\"" | wc -l) -ne 0 ]; then

	    #check if already published
           
	    if [ $(npm view ${package_name}@$version | wc -l) -ne 0 ]; then
		echo "NPM package already published"
                already_published='yes'
	    fi 
	fi
        
	if [ -z "$already_published" ]; then
		echo "Publishing npm package"
                npm publish --access=public
        fi

        echo "Checking and updating frontend dependencies in org:eea"

        check_frontend=$(curl -s  -H "Accept: application/vnd.github.v3+json" -G --data-urlencode "q=org:eea filename:package.json frontend \"$package_name\"" "https://api.github.com/search/code?per_page=100" | grep -iE 'full_name|path":' | awk -F'"' '{ print $4}' )
	
	if [ -z "$check_frontend" ]; then
             echo "Did not find any frontend dependencies"
	     curl -s  -H "Accept: application/vnd.github.v3+json" -G --data-urlencode "q=org:eea filename:package.json frontend \"$package_name\"" "https://api.github.com/search/code?per_page=100"
             exit 0
	fi
       
	for i in $( echo "$check_frontend" ); do 
		if [ -z "$location" ]; then 
			location=$i; 
		else 
			if [ $(echo $i | grep -i frontend | wc -l) -ne 0 ]; then
				update_package_json $i $location $package_name $version
				location=''
			else
				echo "Found $i, but does not contain frontend in it's name, so will skip it"
				location=''
			fi
	        fi 
	done


fi

