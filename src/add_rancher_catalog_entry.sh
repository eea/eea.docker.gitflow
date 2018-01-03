#!/bin/bash

set -e

RANCHER_CATALOG_PATH=templates/www-plone
RANCHER_CATALOR_GITNAME=eea.rancher.catalog
RANCHER_CATALOR_GITSRC=https://github.com/${GIT_ORG}/${RANCHER_CATALOR_GITNAME}.git
DOCKER_IMAGENAME=eeacms/www
DOCKER_IMAGENAME_ESC=$(echo $DOCKER_IMAGENAME | sed 's/\//\\\//g')
 
DOCKER_IMAGEVERSION=14.1


# clone the repo
git clone $RANCHER_CATALOR_GITSRC
cd $RANCHER_CATALOR_GITNAME/$RANCHER_CATALOG_PATH

# get latest rancher entry 

valid_curl_get_result()
{
 url=$1
 check_valid_response=$2
 curl_result=$(curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" $url)
 
 if [ $( echo $curl_result | grep -c "\"$check_valid_response\"" ) -eq 0 ]; then
          echo "There was a problem with the GitHub API request:"
          echo $curl_result
          exit 1
 fi

}

valid_curl_post_result()
{
 url=$1
 data=$2
 check_valid_response=$3
 curl_result=$(curl -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "$data" $url)

 if [ $( echo $curl_result | grep -c "\"$check_valid_response\"" ) -eq 0 ]; then
          echo "There was a problem with the GitHub API request:"
          echo $curl_result
          exit 1
 fi

}




old_version=$(grep version config.yml | awk 'BEGIN{FS="\""}{print $2}')

lastdir=$(grep -l "version: \"$old_version\"" */rancher-compose.yml | awk 'BEGIN{FS="/"}{print $1}')

biggestdirnr=$(find . -maxdepth 1 -type d | awk  'BEGIN{FS="/"}{print $2}' | sort -n | tail -n 1)

if [[ ! "$lastdir" == "$biggestdirnr" ]]; then
 echo "There is a problem with the rancher catalog, please check why current version is not in the latest directory!"
 exit 1
fi

let nextdir=$lastdir+1

echo "Will create new directory, $nextdir"

new_version=$DOCKER_IMAGEVERSION

#get sha from master

GITHUBURL=https://api.github.com/repos/${GIT_ORG}/${RANCHER_CATALOR_GITNAME}/git

valid_curl_get_result ${GITHUBURL}/refs/heads/master sha 
sha_master=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['object']['sha']")


#get docker & rancher config blob sha
valid_curl_get_result ${GITHUBURL}/trees/${sha_master}?recursive=1 tree

eval $(echo $curl_result | python -c "import sys, json
data_dict = json.load(sys.stdin)
for res in data_dict['tree']:
    if res['path'] == \"$RANCHER_CATALOG_PATH/$lastdir/docker-compose.yml\":
        print 'sha_docker_compose="%s";' % res['sha']
    if res['path'] == \"$RANCHER_CATALOG_PATH/$lastdir/rancher-compose.yml\":
        print 'sha_rancher_compose="%s";' % res['sha']
")

valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [{\"path\": \"$RANCHER_CATALOG_PATH/$nextdir/docker-compose.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_docker_compose}\" }, { \"path\": \"$RANCHER_CATALOG_PATH/$nextdir/rancher-compose.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_rancher_compose}\" }]}" sha

sha_newtree=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


# create commit

valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Prepare for release of $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha

sha_new_commit=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


# update master to commit
curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/master)

if [ $( echo $curl_result | grep -c  "HTTP/1.1 200 OK" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
fi

sha_master=$sha_new_commit

# do the changes 
cp -r $lastdir $nextdir
cd $nextdir
sed -i "/    image: $DOCKER_IMAGENAME_ESC:/c\    image: $DOCKER_IMAGENAME_ESC:$new_version"  docker-compose.yml
uuid=$(grep uuid: rancher-compose.yml |  awk 'BEGIN{FS="-"}{gsub (" ", "", $0); x=length($0) - length($NF);  print substr($0,index($0,":")+1,x-index($0,":")) }')
sed -i "/  uuid: /c\  uuid: $uuid$nextdir\"" rancher-compose.yml
sed -i "/  version: /c\  version: \"$new_version\"" rancher-compose.yml
cd ..
sed -i "s/version: \"$old_version\"/version: \"$new_version\"/g" config.yml


#create blobs for changed files

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat config.yml | base64))\",\"encoding\": \"base64\" }" sha
sha_config=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat $nextdir/docker-compose.yml | base64))\",\"encoding\": \"base64\" }" sha
sha_docker_compose=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat  $nextdir/rancher-compose.yml | base64))\",\"encoding\": \"base64\" }" sha
sha_rancher_compose=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

# add in tree copies

valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [{\"path\": \"$RANCHER_CATALOG_PATH/$nextdir/docker-compose.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_docker_compose}\" }, { \"path\": \"$RANCHER_CATALOG_PATH/$nextdir/rancher-compose.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_rancher_compose}\" }, { \"path\": \"$RANCHER_CATALOG_PATH/config.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_config}\" }]}" sha

sha_newtree=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


# create commit

valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Release of $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha

sha_new_commit=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


# update master to commit
curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/master)

if [ $( echo $curl_result | grep -c  "HTTP/1.1 200 OK" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
fi



