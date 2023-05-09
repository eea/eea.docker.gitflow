#!/bin/bash

set -e 

if [ -f /common_functions ]; then
    source /common_functions
elif [ -f ./common_functions ]; then
    source ./common_functions
fi

GIT_BRANCH=${GIT_BRANCH:-master}

update_file()
{

     echo "Updating $3 on branch $2 on package $1"

     GITHUBURL=https://api.github.com/repos/eea/$1

     valid_curl_get_result "$GITHUBURL/contents/$3?ref=$2" sha

     sha_file=$(echo $curl_result | jq '.sha')

     echo "Extracted current sha - $sha_file"

     frontend=${GIT_NAME:-'frontend'}

     valid_curl_put_result "$GITHUBURL/contents/$3" "{\"message\": \"Add Sonarqube tag using $frontend addons list\", \"sha\": ${sha_file}, \"branch\": \"$2\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat $3 | base64))\"}"

     if [ $? -eq 0 ]; then
	     echo "$1, branch $2, $3 updated succesfully"
     fi
}


if [ -z "$SONARQUBE_TOKEN" ] || [ -z "$SONARQUBE_TAG" ] || [ -z "$SONAR_HOST_URL" ] || [ -z "$GIT_TOKEN" ]; then
        echo "Did not receive mandatory parameters SONARQUBE_TOKEN, SONARQUBE_TAG, SONAR_HOST_URL, GIT_TOKEN"
	exit 1
fi	


if [[ $SONARQUBE_TAG =~ "," ]] || [[ $SONARQUBE_TAG =~ " " ]] || [[ $SONARQUBE_TAG =~ "/" ]] ; then
        echo "SONARQUBE_TAG variable should not contain commas(,) spaces( ) or slashes(/)";
        echo "Only one URL is supported per frontend"
        echo "Instead of slash, please use the minus(-) character"
        echo "The tag should be identical to the url that is in the Webscore table"
        exit 1
fi

export GIT_ORG=${GIT_ORG:-'eea'}
export GIT_USER=${GIT_USER:-'eea-jenkins'}
export GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
export GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}


project_result=$(curl -s "${SONAR_HOST_URL}api/components/search_projects?filter=tags%20%3D%20$SONARQUBE_TAG" | grep components )

if [ -z $project_result ]; then
	echo "There is a problem with the sonarqube response"
	curl "${SONAR_HOST_URL}api/components/search_projects?filter=tags%20%3D%20$SONARQUBE_TAG"
else       
	sonarqube_master=$(echo $project_result | jq '.components[] | select(.name | endswith("-master")) | .name[:-7]')
fi

echo "List of projects on sonarqube linked with $SONARQUBE_TAG"
echo $sonarqube_master

if [ ! -f requirements.txt ] && [ -n "$GIT_NAME" ]; then
        echo "Did not find a requirements.txt file, will download it from github for $GIT_NAME @ $GIT_BRANCH"
	wget "https://raw.githubusercontent.com/eea/$GIT_NAME/$GIT_BRANCH/requirements.txt"
else
	echo "Found requirements.txt, will now extract the addons from it"
fi

package_addons=$(cat requirements.txt)


echo "Getting requirements from plone-backend"
if [ ! -f Dockerfile ] && [ -n "$GIT_NAME" ]; then
        echo "Did not find a Dockerfile file, will download it from github for $GIT_NAME @ $GIT_BRANCH"
       wget "https://raw.githubusercontent.com/eea/$GIT_NAME/$GIT_BRANCH/Dockerfile"
fi

if [ $(grep "^FROM eeacms/plone-backend" Dockerfile | wc -l ) -eq 1 ]; then
	
	echo "Found eeacms/plone-backend source, will extract requirements from it"
	plonebackendtag=$(grep "^FROM eeacms/plone-backend" Dockerfile  | tr -d ' \n' | awk -F: '{printf("%s",$2)}' | tr -d '\n')
        echo "Found tag $plonebackendtag, will try to get https://raw.githubusercontent.com/eea/plone-backend/${plonebackendtag}/requirements.txt"
 	
	curl -o plone_requirements.txt  -H 'Accept: application/vnd.github.v3.raw' "https://raw.githubusercontent.com/eea/plone-backend/${plonebackendtag}/requirements.txt"

        package_addons=$(cat requirements.txt plone_requirements.txt)

fi



echo "List of package addons"
echo $package_addons



echo "$package_addons" > /tmp/package_addons


cat /tmp/package_addons | sort -n | uniq > /tmp/all_addons


for package in $(cat /tmp/all_addons); do
    echo "Checking $package" 
    unset check
    check=$(wget -q --spider https://github.com/eea/$package/blob/master/Jenkinsfile  || wget -q --spider https://github.com/eea/$package/blob/master/Jenkinsfile.eea || echo "Not found")

    if [ -z "$check" ]; then

	if [ $(echo $sonarqube_master | grep -w "\"$package\"" | wc -l) -eq 0 ]; then
		#add in Jenkinsfile on develop, add in sonarqube
		echo "Did not find the package in sonarqube with the $SONARQUBE_TAG tag, will try to set it"
		jenkins_file=Jenkinsfile
                rm -f /tmp/Jenkinsfile  
		wget -q "https://raw.githubusercontent.com/eea/$package/develop/$jenkins_file"

		if [ $? -ne 0 ]; then
                    jenkins_file=Jenkinsfile.eea
                    wget -q "https://raw.githubusercontent.com/eea/$package/develop/$jenkins_file"
                fi

		line=$(grep "^ *SONARQUBE_TAGS *= *" $jenkins_file | sed 's/ //g' )
                eval $line
                if [ ! -f $jenkins_file ]; then
                   echo "Could not get Jenkinsfile for $package, on branch develop, skipping package"
		   continue
		fi

		echo "Found line setting sonarqube tags"
		echo $line
		eval $line
		if [ $( echo $SONARQUBE_TAGS | grep -w $SONARQUBE_TAG | wc -l ) -eq 0 ]; then
			SONARQUBE_TAGS=$SONARQUBE_TAGS","$SONARQUBE_TAG
                        UPDATE_JENKINSFILE="yes"
		fi
	        if [[ "$UPDATE_JENKINSFILE" == "yes" ]]; then	
			sed -i "s/ SONARQUBE_TAGS *= *.*/ SONARQUBE_TAGS = \"$SONARQUBE_TAGS\"/" $jenkins_file
			echo "Tag $SONARQUBE_TAG missing, will now add it, setting SONARQUBE_TAGS to $SONARQUBE_TAGS"
			update_file $package "develop" $jenkins_file
		else
			echo "Tag $SONARQUBE_TAG already exists, skipping Jenkinsfile update"
		fi
		rm $jenkins_file
		result=$(curl -XPOST -u "${SONARQUBE_TOKEN}:" "${SONAR_HOST_URL}api/project_tags/set?project=$package-master&tags=${SONARQUBE_TAGS},master")
		if [ $(echo $result | grep error | wc -l ) -ne 0 ]; then
			echo "Receive error when trying to update SonarQube tags"
			echo $result
		else
			echo "Sonarqube tag updated succesfully on sonarqube, project $package-master"
		fi

	else
		echo "Package $package already has correct tags on sonarqube, will skip it"
	fi
   else
	   echo "Package is not EEA repo"
   fi

	echo "---------------------------------------------------------------------------------"
done



