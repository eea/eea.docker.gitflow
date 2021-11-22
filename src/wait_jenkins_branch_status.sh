#!/bin/bash

set -e


# test on volto-test-addon
if [ ! "$GIT_NAME" == "volto-test-addon" ]; then
	exit 0
fi


if [ -z "$GIT_TOKEN" ]; then
 echo "GIT token not given"
 exit 1
fi



if [ -z "$GIT_CHANGE_ID" ] || [[ ! "$GIT_CHANGE_TARGET" == "master" ]] || [[ ! "$GIT_CHANGE_BRANCH" == "develop" ]]; then
  echo "Must run with env variables on PR"
  exit 1
fi


GIT_ORG=${GIT_ORG:-eea}

echo "Starting the script to wait for branch tests to be done"
echo "If the branch tests are failed, will not continue"

echo "https://api.github.com/${GIT_ORG}/${GIT_NAME}/pulls/${GIT_CHANGE_ID} "
pull_request=$(curl -s -X GET -H "Accept: application/vnd.github.v3+json"  -H "Authorization: bearer $GITHUB_TOKEN" "https://api.github.com/${GIT_ORG}/${GIT_NAME}/pulls/${GIT_CHANGE_ID}" | jq -r .statuses_url)


echo "$pull_request"

checks=$(curl -s -X GET -H "Accept: application/vnd.github.v3+json"  -H "Authorization: bearer $GITHUB_TOKEN" "$pull_request" | jq -rc '.[] | select( .context | contains("continuous-integration/jenkins/branch")) |  "\(.created_at) \(.state)" ' )

echo "Found this statuses on the branch job"
echo $checks

cur_status=$(echo $checks | sort -n | tail -n 1 | awk '{print $2}')
wait_for=65

echo "Current status - $cur_status"
while [[ $cur_status == "pending" ]] && [ $wait_for -gt 0 ]; do
   echo "Branch job is still processing, waiting for 30s ......."
   sleep 30 
   checks=$(curl -s -X GET -H "Accept: application/vnd.github.v3+json"  -H "Authorization: bearer $GITHUB_TOKEN" $pull_request | jq -rc '.[] | select( .context | contains("continuous-integration/jenkins/branch")) |  "\(.created_at) \(.state)" ' )
   cur_status=$(echo $checks | sort -n | tail -n | awk '{print $2}')
   wait_for=$((wait_for-1))
done

if [[ $cur_status == "success" ]]; then
        echo "Branch job was processed succesfully, will continue with CHANGELOG modification"
fi

if [[ $cur_status == "error" ]]; then
        echo "Branch job was processed with error, will not continue with CHANGELOG modification to not spam commits"
	exit 1
fi









