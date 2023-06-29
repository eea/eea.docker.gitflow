#!/bin/bash

set -e

echo "Starting frontend release script"

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

export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"




GIT_ORG=${GIT_ORG:-'eea'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}
export GITHUB_TOKEN="${GIT_TOKEN}"

GIT_SRC=https://$GIT_USER:$GIT_TOKEN@github.com/${GIT_ORG}/${GIT_NAME}.git

git config --global user.name "${GIT_USERNAME}"
git config --global user.email "${GITHUB_USER}@users.noreply.github.com"

git clone $GIT_SRC
cd $GIT_NAME
if [ -n "$GIT_CHANGE_ID" ] && [[ "$GIT_CHANGE_TARGET" == "master" ]] && [[ "$GIT_CHANGE_BRANCH" == "develop" ]]; then
        git checkout $GIT_CHANGE_BRANCH
fi
cd ..
	
if [ ! -f $GIT_NAME/package.json ]; then
   rm -rf $GIT_NAME
   echo "Not a javascript package, the check was wrong"
   /docker-entrypoint.sh $@
   exit 0
fi


if [[ ! "${GIT_NAME,,}" =~ ^.*frontend$ ]] &&  [[ ! "${GIT_NAME,,}" =~ ^.*storybook$ ]]; then
   rm -rf $GIT_NAME
   echo "Not a frontend package, the check was wrong"
   /docker-entrypoint.sh $@
   exit 0
fi


cd "$GIT_NAME"


#if PR
if [ -n "$GIT_CHANGE_ID" ] && [[ "$GIT_CHANGE_TARGET" == "master" ]] && [[ "$GIT_CHANGE_BRANCH" == "develop" ]]; then
        
        git checkout $GIT_CHANGE_BRANCH
        existing_tags=$(git tag)

        echo "Check if CHANGELOG exists, if not, create it"


	if [ ! -f CHANGELOG.md ]; then
		touch CHANGELOG.md
	        git add CHANGELOG.md
	        git commit -m "Add empty CHANGELOG.md file"	
	        git push
	fi

	echo "Starting pre-release on PULL REQUEST"

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
        
	
        #if [ $(git diff --name-status ${GIT_CHANGE_BRANCH}..${GIT_CHANGE_TARGET} | wc -l) -eq 0 ]; then
	#	echo "There are no changes to release"
	#	exit 0
	#fi


        echo "Check if format is x.y.z, x.y.z-beta.[0-9]*,  or x.y.z-alpha.[0-9]*"
        if [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | wc -l) -eq 0 ] && [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9\.]+$' | wc -l) -eq 0 ] && [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9\.]+$' | wc -l) -eq 0 ]; then
            echo "Current package.json version $version format is not major.minor.patch nor beta format major.minor.patch-beta.version nor alpha format major.minor.patch-alpha.version"
	    echo "Please manually update the format to a correct version ( major.minor.patch ) "
            exit 1
        fi
 
        /wait_jenkins_branch_status.sh

	if [ $(git tag | grep ^${version}$ | wc -l) -eq 1 ] || [ $(git tag | grep ^v${version}$ | wc -l) -eq 1 ] || [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' | wc -l) -eq 1 ]; then
             echo "Current version is either already released or a beta version"
	     echo "Start release with changelog update on new version"
             echo "Update yarn.lock"

             yarn

             if [ $(yarn -v | grep ^1 | wc -l) -eq 1 ]; then
                echo "Running yarn-deduplicate"
                yarn-deduplicate yarn.lock
             fi

             if [ $(git diff yarn.lock | wc -l) -gt 0 ]; then
                echo "Found changes in yarn.lock, will now update it"
                git add yarn.lock
                git commit -m "chore: [YARN] Automated update of yarn.lock"
             fi

             new_version=$(echo $version | awk -F'[.\-]' '{ print $1"."$2+1".0"}')
	     
             sed -i "s/%2F[0-9]\+\.[0-9]\+\.[0-9]\+\&build=last\&subject=release%20v[0-9]\+\.[0-9]\+\.[0-9]\+%20pipeline/%2F${new_version}\&build=last\&subject=release%20v${new_version}%20pipeline/" README.md
	     sed -i "s#job/[0-9]\+\.[0-9]\+\.[0-9]\+/lastBuild/display#job/$new_version/lastBuild/display#" README.md
	     
             if [ $(git diff README.md | wc -l) -gt 0 ]; then
                echo "Updating README.md with the next release link"
                git add  README.md
                git commit -m "docs: [JENKINS] Automated badge update of README.md"
             fi            

             release-it version=$new_version --config /release-it.json --no-git.tag -i patch --ci
        else
	     echo "Existing version is not yet released, will only auto-update changelog"
             
	     sed -i "s/%2F[0-9]\+\.[0-9]\+\.[0-9]\+\&build=last\&subject=release%20v[0-9]\+\.[0-9]\+\.[0-9]\+%20pipeline/%2F${version}\&build=last\&subject=release%20v${version}%20pipeline/" README.md
	     sed -i "s#job/[0-9]\+\.[0-9]\+\.[0-9]\+/lastBuild/display#job/$version/lastBuild/display#" README.md
	     to_push=""
             if [ $(git diff README.md | wc -l) -gt 0 ]; then
                echo "Updating README.md with the next release link"
                git add  README.md
                git commit -m "docs: [JENKINS] Automated badge update of README.md"
                to_push="yes"
	     fi            

             npx_command=$(grep after:bump /release-it.json | awk -F'"' '{print $4}' | awk -F';' '{print $1}' )
	     
	     sh -c "$npx_command"
	     sed -i '/ Automated release [0-9\.]\+ \|Autobuild of storybook docs\|Add Sonarqube tag using .* addons list\|\[[jJ][eE][nN][kK][iI][nN][sS]\]\|\[[yY][aA][rR][nN]\]/d' CHANGELOG.md
	     
	     if [ $(git diff CHANGELOG.md | tail -n +5 | grep ^+ | grep -Eiv '\- Automated release [0-9\.]+|Autobuild of storybook docs|Add Sonarqube tag using .* addons list|\[[jJ][eE][nN][kK][iI][nN][sS]\]|\[[yY][aA][rR][nN]\]' | wc -l ) -gt 0 ]; then
		     # there were other commits besides the automated release ones"
 	             git add CHANGELOG.md
	             git commit -m "Automated release $version"
                     git push
	     else
	             echo "Did not find any new commits beside the automated ones, will not add them"
		     git checkout -- CHANGELOG.md   
		     
		     if [[ "$to_push" == "yes" ]]; then
		        echo "Will not regenerate CHANGELOG.md, but will update README.md with the new version"
			git push
		     fi
	     fi
	     
	     
	     
	fi
        
fi	




if [ -z "$GIT_CHANGE_ID" ] && [[ "$GIT_BRANCH" == "master" ]] ; then

	
	echo "Starting release on github"


        version=$(grep '"version"' package.json | awk -F'"' '{print $4}')


        echo "Check if format is x.y.z, x.y.z-beta.[0-9]*,  or x.y.z-alpha.[0-9]*"
        if [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | wc -l) -eq 0 ] && [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9\.]+$' | wc -l) -eq 0 ] && [ $(echo $version | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9\.]+$' | wc -l) -eq 0 ]; then
             echo "Version format is not major.minor.patch(-(alpha|beta).version), will skip automated tag creation, please check the error"
	     exit 1
        fi


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
	    
	    /releaseChangelog.sh 

	    body=$(cat releasefile  | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed 's/"/\\\"/g' | sed 's/[R|r]efs #\([0-9]*\)/Refs \[#\1\]\(https:\/\/taskman.eionet.europa.eu\/issues\/\1\)/g' | sed 's/\\\*/\\\\\*/' )


	    curl   -X POST   -H "Accept: application/vnd.github.v3+json"  -H "Authorization: bearer $GITHUB_TOKEN"  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases -d "{\"tag_name\": \"$version\",\"name\": \"$version\", \"target_commitish\":\"${GIT_BRANCH}\",  \"body\":  \"$body\"}" 


        fi


fi

