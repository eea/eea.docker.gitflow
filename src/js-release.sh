#!/bin/bash

set -e

echo "Starting javascript release script"

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


git config --global user.name "${GIT_USERNAME}"
git config --global user.email "${GITHUB_USER}@users.noreply.github.com"

git clone $GIT_SRC

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
	     release-it --no-npm --no-github --no-git.tag -i patch --ci
        else
	     echo "Existing version is not yet released, will only auto-update changelog"
             
	     npx auto-changelog --sort-commits date --commit-limit false -p 
	     if [ $(git diff CHANGELOG.md  | grep ^+- | grep -v 'Automated release' | wc -l ) -gt 0 ]; then
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

        git checkout $GIT_BRANCH

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
	    echo "Starting GitHub release"
            release-it --no-git --no-npm -i patch --ci
        fi

	#check if released

	package_name=$(grep '"name"' package.json | awk -F'"' '{print $4}')

	if [ $(npm search $package_name --json | grep "\"$package_name\"" | wc -l) -ne 0 ]; then

	    #check if already published
           
	    if [ $(npm view ${package_name}@$version | wc -l) -ne 0 ]; then
		echo "NPM package already published"
                exit 0
	    fi 
	fi
        echo "Publishing npm package"
        npm publish --access=public

fi

