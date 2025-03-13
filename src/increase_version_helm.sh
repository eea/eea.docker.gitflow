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

HELM_COMMIT_MESSAGE="${HELM_COMMIT_MESSAGE:-$HELM_UPGRADE_MESSAGE}"
HELM_ADD_COMMIT_LINK_README="${HELM_ADD_COMMIT_LINK_README:-yes}"

echo "Found differences, will now start the version increase"
echo "Version will be increased with $HELM_VERSION_TYPE"
echo "Readme message is $HELM_UPGRADE_MESSAGE"
echo "Commit message is $HELM_COMMIT_MESSAGE"

readme_link=""

if [[ "$HELM_ADD_COMMIT_LINK_README" == "yes" ]]; then
  echo "Will now create a commit only with the changes in the chart used in Changelog"
  git add .
  git commit -m "$HELM_COMMIT_MESSAGE"
  commit=$(git rev-parse HEAD)
  url=$(git config --get remote.origin.url | sed 's|.*github.com[:/]|https://github.com/|' | sed 's|.git$||')/commit/$commit
  readme_link='['$(git log -1 --pretty=format:'%an')' - [`'$(git rev-parse --short HEAD)'`]('$url')]'

fi






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

if [ $(grep "<dl>" part2 | wc -l ) -eq 1 ]; then
    sed -i 's|<[/]*dl>.*||g' part2
    sed -i  's|[ ]*<dt>\(.*\)</dt>|### \1|g' part2
    sed -i  's|[ ]*<dd>\(.*\)</dd>|- \1|g' part2
fi


head -n $line README.md > part1

echo -e "\n### Version $HELM_NEWVERSION - $(LANG=en_us_88591 date +"%d %B %Y")\n- $HELM_UPGRADE_MESSAGE $readme_link" >> part1


cat part1 part2 > README.md

rm part1 part2

echo "Updated README.md with:"

git diff README.md

export HELM_NEWVERSION



