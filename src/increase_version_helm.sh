#!/bin/bash

set -e

if [ ! -f Chart.yaml ]; then

	echo "Please run this script inside a helm chart directory !!!!"
	echo "Exiting"
	exit 1
fi

if  [ $(git diff . | wc -l ) -eq 0 ]; then
	echo "There is nothing to modify!"
	exit 0
fi

if [ $# -eq 1 ]; then
	HELM_VERSION_TYPE=$1
fi

if [[ ! "$HELM_VERSION_TYPE" == "MINOR" ]] && [[ ! "$HELM_VERSION_TYPE" == "MAJOR" ]]; then
    HELM_VERSION_TYPE="PATCH"
fi

if [ -z "$HELM_UPGRADE_MESSAGE" ] ; then
	echo "DID NOT receive HELM_UPGRADE_MESSAGE parameter. It's mandatory for README.md and commit"
        echo "Exiting"
	exit 1
fi

echo "Found differences, will now start the version increase"
echo "Version will be increased with $HELM_VERSION_TYPE"
echo "Message is $HELM_UPGRADE_MESSAGE"


old_version=$(yq -r '.version' Chart.yaml )

v1=$(echo "$old_version" | awk -F. '{print $1}' )
v2=$(echo "$old_version" | awk -F. '{print $2}' )
v3=$(echo "$old_version" | awk -F. '{print $3}' )

if [[ "$HELM_VERSION_TYPE" == "PATCH" ]]; then
   let v3=$v3+1
fi

if [[ "$HELM_VERSION_TYPE" == "MINOR" ]]; then
   let v2=$v2+1
   v3="0"
fi

if [[ "$HELM_VERSION_TYPE" == "MAJOR" ]]; then
   let v1=$v1+1
   v2="0"
   v3="0"
fi


echo "Old version is $old_version, new version is $v1.$v2.$v3 "

HELM_NEWVERSION="${v1}.${v2}.${v3}"

sed -i "s/^version:.*/version: $HELM_NEWVERSION/g" Chart.yaml


line=$(grep -nE "^#+ Releases" README.md | awk -F: '{print $1}')

if [ -z "$line" ]; then

	echo "ERROR Could not find section with Releases in README.md file"
	exit 1
 
fi


sed "1,${line}d" README.md > part2

sed -i "/<dl>/a\  <dt>Version $HELM_NEWVERSION</dt>\n  <dd>$HELM_UPGRADE_MESSAGE</dd>\n" part2

head -n $line README.md > part1

cat part1 part2 > README.md

rm part1 part2

echo "Updated README.md with:"

git diff README.md

export HELM_NEWVERSION



