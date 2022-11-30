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

if [ -f /common_functions ]; then
    source /common_functions
elif [ -f ./common_functions ]; then
    source ./common_functions
fi


GIT_ORG=${GIT_ORG:-'eea'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}
export GITHUB_TOKEN="${GIT_TOKEN}"

GIT_SRC=https://$GIT_USER:$GIT_TOKEN@github.com/${GIT_ORG}/${GIT_NAME}.git

check_and_push()
{
  if [[ "$1" == "yes" ]]; then
        echo "RESOLUTIONS - Updating version on $2@$3 in package.json"
        git diff
	git add package.json
        git commit -m "Release $2@$3 - resolutions"
        git push
  fi
}

update_package_json()
{
       UPDATE_BRANCH="${5:-master}"
       
       if [[ "$1" == "eea/volto-frontend-template" ]]; then
            echo "Skipping frontend template"
	    return
       fi
       
       echo "Running update dependency in $2 on gitrepo $1 for package $3 version $4 on branch $UPDATE_BRANCH"
       
       cd /
       rm -rf /frontend
       git clone https://$GIT_USER:$GIT_TOKEN@github.com/$1.git /frontend
       cd /frontend
       
       if [ $(git branch --all | grep origin/${UPDATE_BRANCH}$ | wc -l) -eq 0 ]; then
          echo "Repository does not contain branch $UPDATE_BRANCH, skipping"
	  return
       fi
              
       git checkout $UPDATE_BRANCH
       
       if [ ! -f "package.json" ]; then
          echo "Repository does not contain package.json, skipping"
	  return
       fi
       
       # check resolutions 
       old_version=$(jq -r ".resolutions | .\"$3\"" package.json )
       biggest_version=$(echo "$4
$old_version" | sort --sort=version | tail -n 1 )

       to_push=""
       
       if [ -z "$old_version" ] || [[ "$old_version" == "None" ]] || [[ "$old_version" == "null" ]] ; then
       	  echo "No RESOLUTIONS to update, skipping"
       elif [ "$4" == "$old_version" ]; then
	  echo "RESOLUTIONS - The released $3 version is already updated"
       elif [ $(echo $old_version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | wc -l) -eq 0 ]; then
	  echo "RESOLUTIONS - Version format ($old_version) is not fixed to major.minor.patch, will not automatically upgrade it"
       elif [[ "$biggest_version" == "$old_version" ]]; then
          echo "RESOLUTIONS - The released $3 version is bigger than the released one, skipping"
       else
          echo "RESOLUTIONS - Old version $old_version is smaller than the released version"
          echo "RESOLUTIONS - Will now update the package.json file"
          jq ".resolutions[\"$3\"] = \"$4\"" package.json > newpackage.json
	  mv newpackage.json package.json
	  to_push="yes"
       fi
       
       
       old_version=$(jq -r ".dependencies | .\"$3\"" package.json )
       
       if [ -z "$old_version" ] || [[ "$old_version" == "None" ]] || [[ "$old_version" == "null" ]] ; then
       	       check_and_push $to_push $3 $4
       	       echo "DEPENDENCIES - Did not find the package in dependecies list, skipping"
 	       return
       fi

       echo "DEPENDENCIES - Found package version - $old_version"

       if [ "$4" == "$old_version" ]; then
	     check_and_push $to_push $3 $4
             echo "DEPENDENCIES - The released $3 version is already updated, finishing"  
	     return
       fi
       echo "Checking prerequisites"
       if [ $(echo $old_version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | wc -l) -eq 0 ]; then
     	    check_and_push $to_push $3 $4
	    echo "DEPENDENCIES - Version format ($old_version) is not fixed to major.minor.patch, will not automatically upgrade it, finishing"
	    return
       fi
       
       biggest_version=$(echo "$4
$old_version" | sort --sort=version | tail -n 1 )

       if [[ "$biggest_version" == "$old_version" ]]; then
      	        check_and_push $to_push $3 $4
                 echo "DEPENDENCIES - The released $3 version is bigger than the released one, finishing"
                 return
       fi
       echo "DEPENDENCIES - Old version $old_version is smaller than the released version"
       echo "DEPENDENCIES - Will now update the version file and yarn.lock"
       
       if [ $(yarn -v | grep ^1 | wc -l) -eq 1 ]; then
           yarn add -W $3@$4
           echo "DEPENDENCIES - Also run deduplicate to fix broken yarn.lock file"
           yarn-deduplicate yarn.lock
       else
           yarn add $3@$4
       fi
       
       #Yarn takes a lot of time, will try pull, if it fails because of conflicts, start over"
       pull_error=$(git pull 2>&1 | grep Aborting | wc -l)
       if [ $pull_error -ne 0 ]; then
          echo "There is a concurrency problem on repo $1, will cleanup and retry again"
          update_package_json $1 $2 $3 $4 $5
	  return
       fi
       git status
       git diff
       git add package.json
       if [ $(grep "yarn.lock" .gitignore | wc -l ) -eq 0 ]; then
           git add yarn.lock
       fi
       commit_ok=$(git commit -m "Release $3@$4" | grep -i "changed" | wc -l)
       if [ $commit_ok -eq 1 ]; then
         git push
       else
         echo "There was a problem with the commit on repo $1, will cleanup and retry again"
         update_package_json $1 $2 $3 $4 $5
	 return
       fi
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

        /wait_jenkins_branch_status.sh

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
	     
	     if [ -z "$GIT_CHANGE_TITLE" ]; then
	     	valid_curl_get_result https://api.github.com/repos/$GIT_ORG/$GIT_NAME/pulls/$GIT_CHANGE_ID title
	     	GIT_CHANGE_TITLE=$(echo $curl_result | jq -r ".title")
	     	echo "Extracted PR title - $GIT_CHANGE_TITLE"
             fi
	     
	     RELEASE_TYPE="patch"
	     
             if [ $(echo "$GIT_CHANGE_TITLE" | grep "^MINOR:" | wc -l ) -eq 1 ]; then
	       echo "Will use a MINOR version for release, title of PR is $GIT_CHANGE_TITLE"
               RELEASE_TYPE="minor"
	     fi
	     
	     if [ $(echo "$GIT_CHANGE_TITLE" | grep "^MAJOR:" | wc -l ) -eq 1 ]; then
  	       echo "Will use a MAJOR version for release, title of PR is $GIT_CHANGE_TITLE"
               RELEASE_TYPE="major"
	     fi
	     
	     release-it --config /release-it.json --no-git.tag -i $RELEASE_TYPE --ci
        else
	     echo "Existing version is not yet released, will only auto-update changelog"
             
	     npx_command=$(grep after:bump /release-it.json | awk -F'"' '{print $4}' | awk -F';' '{print $1}' )
	     
	     sh -c "$npx_command"
	     sed -i '/ Automated release [0-9\.]\+ \|Add Sonarqube tag using .* addons list\|\[[jJ][eE][nN][kK][iI][nN][sS]\|[yY][aA][rR][nN]/d' CHANGELOG.md

	     if [ $(git diff CHANGELOG.md | tail -n +5 | grep ^+ | grep -Eiv '\- Automated release [0-9\.]+|Add Sonarqube tag using .* addons list|\[jenkins|yarn' | wc -l ) -gt 0 ]; then

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
	    if [[ "$GIT_NAME" == "volto-eea-kitkat" ]]; then
	        /releaseChangelog.sh
		cat releasefile
		
		body=$(cat releasefile  | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed 's/"/\\\"/g' )
		echo  "{\"tag_name\": \"$version\",\"name\": \"$version\", \"target_commitish\":\"${GIT_BRANCH}\",  \"body\":  \"$body\"}" 

	    else
	        body=$(npx auto-changelog --stdout --sort-commits date-desc --commit-limit false -u --template /release.hbs --ignore-commit-pattern 'Automated release [0-9\.]+ |Add Sonarqube tag using .* addons list|\[[jJ][eE][nN][kK][iI][nN][sS]|[yY][aA][rR][nN]' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed 's/"/\\\"/g')
	    fi

            body=$(echo "$body" | sed 's/[R|r]efs #\([0-9]*\)/Refs \[#\1\]\(https:\/\/taskman.eionet.europa.eu\/issues\/\1\)/g' )

            echo "{\"tag_name\": \"$version\",\"name\": \"$version\", \"target_commitish\":\"${GIT_BRANCH}\",  \"body\":  \"$body\"}"

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
		
		echo "Checking if prepublish script exist"
		if [ $(cat  package.json | jq '.scripts.prepublish | length') -gt 0 ]; then
		   echo "Found prepublish script, running it"
		   yarn 
		   yarn prepublish
		fi
		
		
                npm publish --access=public
		echo "Waiting for npm to sync their data for yarn before updating frontends"
		sleep 60
        fi


        echo "Check if format is x.y.z"
	if [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | wc -l) -eq 0 ]; then
	    echo "Version format is not major.minor.patch, will skip frontend and kitkat update"
	    exit 0
	fi

        echo "Checking and updating frontend dependencies in org:eea"

        check_frontend=$(curl -s  -H "Accept: application/vnd.github.v3+json" -G --data-urlencode "q=org:eea frontend in:name" "https://api.github.com/search/repositories?per_page=100" | jq -r .items[].full_name )
	
	current_pwd="$(pwd)"
	
	for i in $( echo "$check_frontend" ); do 
	    update_package_json $i package.json $package_name $version develop
        done

        check_kitkat=$(curl -s  -H "Accept: application/vnd.github.v3+json" -G --data-urlencode "q=org:eea kitkat in:name volto in:name" "https://api.github.com/search/repositories?per_page=100" | jq -r .items[].full_name )
       
	for i in $( echo "$check_kitkat" ); do 
            update_package_json $i package.json $package_name $version develop
        done
	
	cd $current_pwd
fi

