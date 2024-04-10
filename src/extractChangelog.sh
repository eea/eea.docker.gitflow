#!/bin/bash

if [ -z "$changeFile" ]; then
	if [ -n "$GIT_HISTORYFILE" ]; then
		changeFile="$GIT_HISTORYFILE"
	else
		changeFile=$(grep GIT_HISTORYFILE Jenkinsfile | head -n 1 | awk -F= '{print $2}' | tr -d ' ' | tr -d '"')

	fi
fi

changeFile=${changeFile:-'docs/HISTORY.txt'}

#make sure format is good
dos2unix $changeFile

rm -f releasefile

if [ -z "$version" ]; then
	version=$1
fi

if [ -z "$version" ]; then
	echo "Did not receive version variable or first argument"
        exit 1
fi


line_nr=$(grep -nE "^$version .*\([0-9]*.*\)" $changeFile | head -n 1 | awk -F: '{print $1-1}')
first_line=""
last_line=""

if [ -z "$line_nr" ]; then
	echo "DID not find the version $version in the changelog - $changeFile"
        touch releasefile
	exit 0
fi

echo "found version information on line $line_nr on $changeFile"

for i in $(grep -n '^----------.*$' $changeFile  | awk -F: '{print $1}'); do
     if [ -z "$first_line" ] && [ "$i" -gt "$line_nr" ]; then
	     first_line=$((i+1))
	     continue
     fi
     if [ -n "$first_line" ] && [ -z "$last_line" ]; then
	     last_line=$((i-2))
	     break
     fi
done


if [ -z "$last_line" ]; then
  last_line=$(wc -l $changeFile | awk '{print $1}'  )
fi

sed -n "${first_line},${last_line}p" $changeFile | awk 'NF' | sed 's/#\([0-9]\{5,6\}\)/\[#\1\]\(https:\/\/taskman.eionet.europa.eu\/issues\/\1\)/g' > releasefile
 
truncate -s -1 releasefile

echo "Parsed lines ${first_line},${last_line} from $changeFile"

