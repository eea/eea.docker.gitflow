#!/bin/bash

set -e

GIT_ORG=${GIT_ORG:-eea}
GIT_PR_TARGET=${GIT_PR_TARGET:-develop}

if [ -z "$GIT_BRANCH" ] || [ -z "$GIT_NAME" ]; then
    echo "Script needs at least source branch and repository name"
fi


if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi



https://api.github.com/repos/eea/volto-editing-progress/pulls


valid_curl_get_list_result "https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/pulls"

number_prs=$(echo "$curl_result" | jq 'length')

if [ "$number_prs" -eq 0 ]; then
	echo "There are no pull requests on /${GIT_ORG}/${GIT_NAME}"
	exit 0
fi

echo "There are $number_prs pull requests on /${GIT_ORG}/${GIT_NAME}, checking them ..."


if [ $(echo "$curl_result" | jq '.[] | select( .head.ref == "$GIT_BRANCH" and .base.ref == "$GIT_PR_TARGET" and .head.repo.full_name == "${GIT_ORG}/${GIT_NAME}" and .base.repo.full_name == "${GIT_ORG}/${GIT_NAME}" ) | .url ' | wc -l) -eq 0 ]; then
	echo "Did not find any PRs created from branch $GIT_BRANCH to branch $GIT_PR_TARGET"
	exit 0
fi
echo "FOUND PR from $GIT_BRANCH to branch $GIT_PR_TARGET"
echo "$curl_result" | jq '.[] | select( .head.ref == "$GIT_BRANCH" and .base.ref == "$GIT_PR_TARGET" and .head.repo.full_name == "${GIT_ORG}/${GIT_NAME}" and .base.repo.full_name == "${GIT_ORG}/${GIT_NAME}" ) | .url ' 

exit 1



