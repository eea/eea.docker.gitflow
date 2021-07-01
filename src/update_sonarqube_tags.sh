#!/bin/bash



if [ -z "$URL" ] || [ -z "$SONARQUBE_TOKEN" ] || [ -z "$SONARQUBE_TAG" ] || [ -z "$SONAR_HOST_URL" ]; then
        

project_result=$(curl -s "${SONAR_HOST_URL}api/components/search_projects?filter=tags%20%3D%20$SONARQUBE_TAG" | grep components )

if [ -z $project_result ]; then
	echo "There is a problem with the sonarqube response"
	curl "${SONAR_HOST_URL}api/components/search_projects?filter=tags%20%3D%20$SONARQUBE_TAG"
else       
	sonarqube_master=$(echo $project_result | jq '.components[] | select(.name | endswith("-master")) | .name[:-7]')
fi

package_addons=$(cat package.json | jq '.addons[] | select(.|startswith("@eeacms") or startswith("volto-slate:"))' | sed 's/@eeacms\///' | sed 's/:asDefault//')



for package in $package_addon; do
	if [ $(echo $sonarqube_master | grep -w "$package" | wc -l) -eq 0 ]; then
		#add in Jenkinsfile on develop, add in sonarqube
		echo "Did not find the package in sonarqube with the $SONARQUBE_TAG tag, will try to set it"
		wget "https://raw.githubusercontent.com/eea/$package/develop/Jenkinsfile"

		line=$(grep "^ *SONARQUBE_TAGS *= *" Jenkinsfile | sed 's/ //g' )
                eval $line

		if [ $( echo $line | grep -w $SONARQUBE_TAG | wc -l ) -eq 0 ]; then
                	eval $line
			SONARQUBE_TAGS=$SONARQUBE_TAGS","$SONARQUBE_TAG
			sed -i 's/ SONARQUBE_TAGS *= *.*/SONARQUBE_TAGS = $SONARQUBE_TAGS/' Jenkinsfile
			update_file($package,"develop","Jenkinsfile")
		fi
                try=2; while [ \$try -gt 0 ]; do curl -s -XPOST -u "${SONAR_AUTH_TOKEN}:" "${SONAR_HOST_URL}api/project_tags/set?project=$package-master&tags=${SONARQUBE_TAGS},master" > set_tags_result; if [ \$(grep -ic error set_tags_result ) -eq 0 ]; then try=0; else cat set_tags_result; echo "... Will retry"; sleep 60; try=\$(( \$try - 1 )); fi; done

	fi
done




