#!/bin/bash

set -e

# script that runs on PR and exits successfully only if github branch check on jenkins is successfull
# waits if the status is "pending"
# exits with error otherwise

if [ -z "$GIT_TOKEN" ]; then
 echo "GIT token not given"
 exit 1
fi



if [ -z "$GIT_CHANGE_ID" ] || [[ ! "$GIT_CHANGE_TARGET" == "master" ]] || [[ ! "$GIT_CHANGE_BRANCH" == "develop" ]]; then
  echo "Must run with env variables on PR"
  exit 1
fi


GIT_ORG=${GIT_ORG:-eea}



curl_get_result()
{
 max_retry=10
 get_url="$1"
 check_valid_response=$2
 curl_result=$(curl -s -X GET  -H "Accept: application/vnd.github.v3+json" -H "Authorization: bearer $GIT_TOKEN" "$get_url")
 retry=1
 while [ -z "$curl_result" ] || [ $(echo "$curl_result" | grep "$check_valid_response" | wc -l ) -eq 0 ]; do

          echo "There was a problem with the GitHub API get request for $get_url"
	  echo "Will retry now ... try number $retry"
          echo $curl_result
          
          curl_result=$(curl -s -X GET  -H "Accept: application/vnd.github.v3+json" -H "Authorization: bearer $GIT_TOKEN" "$get_url")

	  retry=$((retry+1))
	  if [ $retry -gt $max_retry ]; then
	      echo "Could not get response from github api on url $get_url for 10 minutes"
	      echo "Will exit now"
	      exit 1	
	  fi
          sleep 60	  
 done

}


echo "Starting the script to wait for branch tests to be done"
echo "If the branch tests are failed, will not continue"

curl_get_result "https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/pulls/${GIT_CHANGE_ID}" statuses_url

pull_request=$( echo $curl_result | jq -r .statuses_url)

curl_get_result $pull_request "continuous-integration/jenkins/branch"

checks=$( echo $curl_result | jq -rc '.[] | select( .context | contains("continuous-integration/jenkins/branch")) |  "\(.created_at) \(.state)" ' )

echo "Found this statuses on the branch job"
echo $checks

cur_status=$(echo $checks | sort -n | tail -n 1 | awk '{print $2}')
wait_for=130

echo "Current status - $cur_status"
while [[ $cur_status == "pending" ]] && [ $wait_for -gt 0 ]; do
   echo "Branch job is still processing, waiting for 30s ......."
   sleep 30 
   
   curl_get_result $pull_request "continuous-integration/jenkins/branch"

   checks=$( echo $curl_result | jq -rc '.[] | select( .context | contains("continuous-integration/jenkins/branch")) |  "\(.created_at) \(.state)" ' )

   cur_status=$(echo $checks | sort -n | tail -n 1 | awk '{print $2}')
   wait_for=$((wait_for-1))
done


if [[ $cur_status == "success" ]]; then
        echo "Branch job was processed succesfully, will continue with CHANGELOG modification"
        exit 0
fi

if [[ $cur_status == "error" ]]; then
        echo "Branch job was processed with error, will not continue with CHANGELOG modification to not spam commits"
	exit 1
fi

echo "Received status $cur_status, will not continue with the processing"
exit 1

