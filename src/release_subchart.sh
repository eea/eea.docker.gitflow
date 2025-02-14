#!/bin/bash

set -e

if [ -z "$CI" ]; then

  echo "Usage ./release_subchart sources/NAME"
  echo "Usage ./release_subchart NAME"
  echo "Usage ./release_subchart sources/NAME VERSION"
  echo "Default version is latest version"

  if [ $(yq -V | grep version | wc -l ) -ne 1 ]; then

    echo "This script uses yq to update yaml files. You need to have it installed"
    echo "Use https://github.com/mikefarah/yq"
    echo "To install latest version run: "
    echo "wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq" 

    exit 1
  fi
fi


if [ $# -gt 0 ]; then

 HELM_SUBCHART=$( echo $1 | sed 's/sources//g' | sed 's|/||g' )
 HELM_SUBCHART_VERSION=$2

fi

if [ -z "$HELM_SUBCHART" ]; then

	echo "This script needs to receive the HELM_SUBCHART variable"
	exit 1
fi

if [ -z "$HELM_SUBCHART_VERSION" ]; then
       echo "Did not receive the version, will use latest version"
       HELM_SUBCHART_VERSION=$(yq '.version' sources/$HELM_SUBCHART/Chart.yaml )
       echo $HELM_SUBCHART_VERSION

fi



echo " Trying to update subchart $HELM_SUBCHART version $HELM_SUBCHART_VERSION in all charts "

export HELM_VERSION_TYPE="PATCH"
export HELM_UPGRADE_MESSAGE="Release of dependent chart $HELM_SUBCHART:$HELM_SUBCHART_VERSION"

for i in $(grep $HELM_SUBCHART sources/*/Chart.yaml | awk -F: '{print $1}' | awk -F"/" '{print $2}' | uniq ); do


        old_version=$( yq ".dependencies[] | select ( .name == \"$HELM_SUBCHART\" ) | .version"  sources/$i/Chart.yaml )

	if [ -z $old_version ] && [ ! "$old_version" == "null" ]; then 
		continue;
	fi

        if [ "$old_version" == "$HELM_SUBCHART_VERSION" ]; then
                
		echo "Found $i, Subchart $HELM_SUBCHART already version $HELM_SUBCHART_VERSION, skipping"
		continue;
	fi 
 
	bigger_version=$(echo -e "$old_version\n$HELM_SUBCHART_VERSION" | sort -V | tail -n 1)
     
        if [ "$bigger_version" == "$old_version" ]; then

		echo  "Found $i, Subchart $HELM_SUBCHART has current version, $old_version bigger than $HELM_SUBCHART_VERSION, skipping"
                continue;
        fi        

        echo "Updating version"
      
	cd sources/$i

	yq -i "( .dependencies[] | select ( .name == \"$HELM_SUBCHART\" ) | .version ) = \"$HELM_SUBCHART_VERSION\""  Chart.yaml
        
	../../increase_version_helm.sh
        
        cd ../..

        ./update_docs.sh $i  
        
done

echo "Finished updating subcharts"




