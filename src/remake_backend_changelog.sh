#!/bin/bash

echo "Give repo name - example eea/eea-website-backend"
read repo
echo "Repo is $repo"

echo "Continue ? Enter for yes, anything else to stop"
read var
if [ -n "$var" ]; then echo "Will stop now"; exit 0; fi


tags=$(curl -s "https://api.github.com/repos/$repo/releases?per_page=100" | jq -r '.[].tag_name')

 for i in $(echo "$tags"); do
 old=$(echo "$tags" | grep -A 1 "^$i$" | grep -v "^$i$")

 ./pyreleaseChangelog.sh $repo $i $old; done


releases=$(curl  https://api.github.com/repos/$repo/releases?per_page=100)

echo -e '# Changelog\n\n' > CHANGELOG.md
echo "$releases" | jq -r '.[] | "@%@%@ [\(.tag_name)](https://github.com/$repo/releases/tag/\(.tag_name)) - \(.published_at)\n\n\(.body)"' | sed 's/^#/###/g' | sed 's/@%@%@/##/g'| sed 's/######[#]*/######/g'  | sed 's/\[#\([0-9]\{5,6\}\)\](https:\/\/taskman.eionet.europa.eu\/issues\/[0-9]\{5,6\})/#\1/g'  >> CHANGELOG.md


