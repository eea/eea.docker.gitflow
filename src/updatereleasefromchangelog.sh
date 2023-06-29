#!/bin/bash

set -e

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to work"
   exit 1
fi

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi



repository=$1

if [ $(grep "^$1$" list_done | wc -l) -eq 1 ]; then
	echo "Already updated"
	exit 0
fi	


curl_res=$(curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" https://api.github.com/repos/$repository/releases?per_page=10)

releases=$(echo "$curl_res"| jq -r ".[].tag_name" )

if [ -z "$releases" ] || [[ "$releases" == "null" ]]; then
      echo "No releases found"
      echo $repository >> list_done
      echo "$repository no releases" >> list_error
      exit 0
fi

rm -rf repo

git clone git@github.com:$repository.git repo

cd repo

changeFile=$(grep GIT_HISTORYFILE Jenkinsfile | head -n 1 | awk -F= '{print $2}' | tr -d ' ' | tr -d '"')

export changeFile=${changeFile:-'docs/HISTORY.txt'}

echo "Changefile is $changeFile"

if [ ! -f "$changeFile" ]; then
   echo "changefile $changeFile does not exist"
      echo $repository >> ../list_done
      echo "$repository no changefile, $changeFile" >> ../list_error

   exit 1
fi

for i in $(echo $releases); do

echo "Start release $i"

valid_curl_get_result "https://api.github.com/repos/$repository/releases/tags/$i"

../extractChangelog.sh "$i" 


echo "received release text:"

cat releasefile

id=$(echo "$curl_result" | jq -r ".id")

echo $curl_result  | jq --rawfile body releasefile '{"body": $body}' > body.json

echo ""

echo "https://api.github.com/repos/$repository/releases/$id"

echo ""

curl -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" "https://api.github.com/repos/$repository/releases/$id" -d @body.json

done

cd ..

echo $repository >> list_done




