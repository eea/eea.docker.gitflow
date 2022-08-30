#!/bin/bash

if [ -z "$changeFile" ]; then
	if [ -n "$GIT_HISTORYFILE"]; then
		changeFile="$GIT_HISTORYFILE"
	else
		changeFile=$(grep GIT_HISTORYFILE Jenkinsfile | head -n 1 | awk -F= '{print $2}' | tr -d ' ' | tr -d '"')

	fi
fi

changeFile=${changeFile:-'docs/HISTORY.txt'}
if [ -z "$version" ]; then
	version=$1
fi

if [ -z "$version" ]; then
	echo "Did not receive version variable or first argument"
        exit 1
fi


line_nr=$(grep -nE "^$version - (.*)" $changeFile | tail -n 1 | awk -F: '{print $1-1}')
first_line=""
last_line=""

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


sed -n "${first_line},${last_line}p" $changeFile | awk 'NF' 


