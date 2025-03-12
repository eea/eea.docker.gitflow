#!/bin/bash

set -e

GIT_ORG=${GIT_ORG:-'eea'}
RANCHER_CATALOG_GITNAME=${RANCHER_CATALOG_GITNAME:-'eea.rancher.catalog'}

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to create releases"
   exit 1
fi

if [ -z "$RANCHER_CATALOG_PATH" ] || [ -z "$DOCKER_IMAGENAME" ] || [ -z "$DOCKER_IMAGEVERSION" ]; then
   if [ "$#" -ge 3 ]; then
       echo "Did not receive parameters from environment, will try to parse them from arguments"
       RANCHER_CATALOG_PATH=$1
       DOCKER_IMAGENAME=$2
       DOCKER_IMAGEVERSION=$3
       if [ -n $4 ]; then
           RANCHER_CATALOG_SAME_VERSION=$4
       fi	   
   else
       echo "Problem with creating rancher catalog entry, missing parameters"
       exit 1
   fi
fi

echo "Checked parameters, will start creating catalog entry on ${GIT_ORG}/${RANCHER_CATALOG_GITNAME} on path ${RANCHER_CATALOG_PATH}, for ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}, with keeping same version = ${RANCHER_CATALOG_SAME_VERSION}"

RANCHER_CATALOG_GITSRC=https://github.com/${GIT_ORG}/${RANCHER_CATALOG_GITNAME}.git
DOCKER_IMAGENAME_ESC=$(echo $DOCKER_IMAGENAME | sed 's/\//\\\//g')
GITHUBURL=https://api.github.com/repos/${GIT_ORG}/${RANCHER_CATALOG_GITNAME}/git
current_dir=$(pwd)

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi

# clone the repo
rm -rf $RANCHER_CATALOG_GITNAME
git clone $RANCHER_CATALOG_GITSRC

if [ -d $RANCHER_CATALOG_GITNAME/$RANCHER_CATALOG_PATH ]; then
   cd $RANCHER_CATALOG_GITNAME/$RANCHER_CATALOG_PATH
else
   echo "Received RANCHER_CATALOG_PATH a path that does not exist - $RANCHER_CATALOG_PATH, will exit script without changes"
   echo "Return exit code succesfull for the case of migration from rancher catalog to helm"
   echo "Please check variable value if is configured correctly"
   exit 0
fi

# get latest rancher entry


old_version=$(grep "^version: " config.yml | awk -F: '{print $2}' | sed  "s/[' \"]//g")

lastdir=$(grep -l "version: [ '\"]*$old_version[ '\"]*$" */rancher-compose.yml | awk 'BEGIN{FS="/"}{print $1}' | sort -n | tail -n 1 )

biggestdirnr=$(find . -maxdepth 1 -type d | awk  'BEGIN{FS="/"}{print $2}' | sort -n | tail -n 1)



if [[ ! "$lastdir" == "$biggestdirnr" ]]; then
 echo "There is a problem with the rancher catalog, please check why current version is not in the latest directory!"
 echo "Current version - $lastdir, biggest dir - $biggestdirnr"
 exit 1
fi


if [ -n "$RANCHER_CATALOG_READ_VERSION" ]; then
  echo "Last catalog version is $old_version, write the next version you want to create to release ${DOCKER_IMAGENAME}:${DOCKER_IMAGEVERSION}"
  read new_version
  if [ -n "$new_version" ]; then
      echo "Received $new_version value, to continue press ENTER. If you want to stop the script, press N"
      read confirm
      if  [[ "$confirm" == "N" ]] || [[ "$confirm" == "n" ]]; then
	exit 0
      fi	
  else
      echo "Did not receive any value, will use the default - $DOCKER_IMAGEVERSION"
  fi
else
  if [ -n "$RANCHER_CATALOG_ADD_MINUS" ]; then
      echo "catalog version - Adding -1 to existing version: ${old_version}-1"
      new_version="${old_version}-1"
  else
    if [ -n "${RANCHER_CATALOG_VERSION}" ]; then
      new_version="${RANCHER_CATALOG_VERSION}"
    else
       # Auto generate Rancher Catalog next version or use the Docker Image version
       if [ -n "$RANCHER_CATALOG_NEXT_VERSION" ]; then
          new_version=$(echo $old_version | awk '{printf "%.1f-dev0", $1 + 0.1}' )
       else
          new_version=$DOCKER_IMAGEVERSION
       fi
    fi
  fi
fi


# Modify the same latest Rancher Catalog entry or generate new one?
if [ -z "$RANCHER_CATALOG_SAME_VERSION" ]; then
  let nextdir=$lastdir+1
  echo "Will create new directory, $nextdir"
else
  let nextdir=$lastdir
  new_version=$old_version
  echo "will use same directory for update, $nextdir"
fi



DOCKER_COMPOSE=$(ls $lastdir | grep docker-compose.yml )

echo "--------------------------------------------------------"
if [ $(grep  "image: $DOCKER_IMAGENAME_ESC:$DOCKER_IMAGEVERSION$"  */$DOCKER_COMPOSE | wc -l ) -gt 0 ]; then
  echo "Found in old template $DOCKER_COMPOSE images with $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION"
  echo "Will skip the creation of new version of rancher catalog!"
  #clean-up
  cd $current_dir
  rm -rf $RANCHER_CATALOG_GITNAME
  exit 0
fi



echo "--------------------------------------------------------"
if [ $(grep "image: ${DOCKER_IMAGENAME_ESC}:" $lastdir/$DOCKER_COMPOSE | grep -v gitflow-disable | wc -l ) -eq 0 ]; then
  echo "Did not find in latest $DOCKER_COMPOSE images with $DOCKER_IMAGENAME without gitflow-disable nor with a version to be upgraded"
  echo "Will skip the creation of new version of rancher catalog!"
  #clean-up
  cd $current_dir
  rm -rf $RANCHER_CATALOG_GITNAME
  exit 0
fi



smallest_version=$(grep "image: ${DOCKER_IMAGENAME_ESC}:" $lastdir/$DOCKER_COMPOSE | grep -v gitflow-disable | awk -F: '{print $3}' | sort --sort=version | head -n 1 )

bigger_version=$(echo "$DOCKER_IMAGEVERSION
$smallest_version" | sort --sort=version | tail -n 1 )

if [[ ! "$bigger_version" == "$DOCKER_IMAGEVERSION" ]]; then
  echo "Version ${DOCKER_IMAGEVERSION} is smaller than the smallest image version ${smallest_version}, will skip rancher catalog"
  cd $current_dir
  rm -rf $RANCHER_CATALOG_GITNAME
  exit 0
fi




echo "Checked latest $DOCKER_COMPOSE ($lastdir/$DOCKER_COMPOSE), $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION is not present, will go on with creating the new rancher catalog version!"

echo "--------------------------------------------------------"



# get sha from master
valid_curl_get_result ${GITHUBURL}/refs/heads/master object.sha
sha_master=$(echo $curl_result |  jq -r '.object.sha // empty' )

# Create new Rancher Catalog entry
if [ -z "$RANCHER_CATALOG_SAME_VERSION" ]; then

 
  #get docker & rancher config blob sha
  valid_curl_get_result ${GITHUBURL}/trees/${sha_master}?recursive=1 tree


  eval $(echo $curl_result | python -c "
import sys, json
data_dict = json.load(sys.stdin)

for res in data_dict['tree']:
	if res['path'].find('$RANCHER_CATALOG_PATH/$lastdir/') == 0:
		print('sha_list=\"\$sha_list '+res['sha']+';'+res['path'].replace('$RANCHER_CATALOG_PATH/$lastdir/','$RANCHER_CATALOG_PATH/$nextdir/')+'\"')
		")

  # echo $sha_list
  tree_list=""

  for path in $sha_list ; do 
       IFS=';' read -ra tree_node <<< "$path"
       tree_list="$tree_list {\"path\": \"${tree_node[1]}\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${tree_node[0]}\" },"
  done
  tree_list=${tree_list:1:-1}
  tree_list="[$tree_list]" 
  # echo $tree_list  
  valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": $tree_list}" sha

  sha_newtree=$(echo $curl_result |  jq -r '.sha // empty')


  # create commit

  valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Prepare for release of $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha

  sha_new_commit=$(echo $curl_result |  jq -r '.sha // empty')


  # update master to commit
  curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/master)

  if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 200" ) -eq 0 ]; then
              echo "There was a problem with the commit on master"
              echo $curl_result
              exit 1
  fi

  sha_master=$sha_new_commit

  echo "Finished with prerelease commit - added new entry $RANCHER_CATALOG_PATH/$nextdir"
  # do the changes
  cp -r $lastdir $nextdir
fi

# Update Rancher Catalog entry

cd $nextdir


sed -i -e "/gitflow-disable/! s/    image: ${DOCKER_IMAGENAME_ESC}:.*${DOCKERHUB_REPO_SUFIX}$/    image: ${DOCKER_IMAGENAME_ESC}:${DOCKER_IMAGEVERSION}${DOCKERHUB_REPO_SUFIX}/" -e "/gitflow-disable/! {/image: ${DOCKER_IMAGENAME_ESC}:${DOCKER_IMAGEVERSION}${DOCKERHUB_REPO_SUFIX}/! s/    image: ${DOCKER_IMAGENAME_ESC}:.*/    image: ${DOCKER_IMAGENAME_ESC}:${DOCKER_IMAGEVERSION}/}" $DOCKER_COMPOSE
sed -i "/  version: /c\  version: \"$new_version\"" rancher-compose.yml


cd ..
sed -i "s/version: \"$old_version\"/version: \"$new_version\"/g" config.yml

if [ -f 'auto_release.sh' ]; then
        . auto_release.sh
fi


#create blobs for changed files

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat config.yml | base64))\",\"encoding\": \"base64\" }" sha
sha_config=$(echo $curl_result |  jq -r '.sha // empty')

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat $nextdir/$DOCKER_COMPOSE | base64))\",\"encoding\": \"base64\" }" sha
sha_docker_compose=$(echo $curl_result |  jq -r '.sha // empty')

valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat  $nextdir/rancher-compose.yml | base64))\",\"encoding\": \"base64\" }" sha
sha_rancher_compose=$(echo $curl_result |  jq -r '.sha // empty')

# add in tree copies

valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_master}\",\"tree\": [{\"path\": \"$RANCHER_CATALOG_PATH/$nextdir/$DOCKER_COMPOSE\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_docker_compose}\" }, { \"path\": \"$RANCHER_CATALOG_PATH/$nextdir/rancher-compose.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_rancher_compose}\" }, { \"path\": \"$RANCHER_CATALOG_PATH/config.yml\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_config}\" }]}" sha

sha_newtree=$(echo $curl_result |  jq -r '.sha // empty')


# create commit

valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Release of $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION\", \"parents\": [\"${sha_master}\"], \"tree\": \"${sha_newtree}\"}"  sha

sha_new_commit=$(echo $curl_result |  jq -r '.sha // empty')


# update master to commit
curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/master)

if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 200" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
fi

echo "Successfully finished the release of $DOCKER_IMAGENAME:$DOCKER_IMAGEVERSION in catalog"
#clean-up
cd $current_dir
rm -rf $RANCHER_CATALOG_GITNAME
