#!/bin/bash

set -e

export PYTHONIOENCODING=utf8


if [ -z "$GIT_NAME" ]; then
 echo "GIT repo name not given"
 exit 1
fi

if [ -z "$GIT_ORG" ]; then
 GIT_ORG="eea"
fi

GIT_SRC=https://github.com/${GIT_ORG}/${GIT_NAME}.git

if [ -z "$GIT_VERSIONFILE" ]; then
  GIT_VERSIONFILE="$(echo $GIT_NAME | sed 's|\.|/|g')/version.txt"
fi

if [ -z "$GIT_HISTORYFILE" ]; then
  GIT_HISTORYFILE="docs/HISTORY.txt"
fi

if [ -z "$GIT_USERNAME" ]; then
 GIT_USERNAME="EEA Jenkins"
fi

if [ -z "$GIT_EMAIL" ]; then
 GIT_EMAIL="eea-github@googlegroups.com"
fi

if [ -z "$EGGREPO_URL" ]; then
 EGGREPO_URL=https://eggrepo.eea.europa.eu/
fi

if [ -z "$KGS_GITNAME" ]; then
  KGS_GITNAME=eea.docker.kgs
fi

if [ -z "$KGS_VERSIONS_PATH" ]; then
  KGS_VERSIONS_PATH=src/plone/versions.cfg
fi


if [ -z "$DOCKERHUB_REPO" ]; then
  DOCKERHUB_REPO="eeacms/kgs"
fi

if [ -z "$TIME_TO_WAIT_RELEASE" ]; then
  TIME_TO_WAIT_RELEASE=240
fi

if [ -z "$TIME_TO_WAIT_START" ]; then
  TIME_TO_WAIT_START=30
fi


export GIT_ORG GIT_SRC GIT_VERSIONFILE GIT_HISTORYFILE GIT_USERNAME GIT_EMAIL EGGREPO_URL KGS_GITNAME KGS_VERSIONS_PATH DOCKERHUB_REPO TIME_TO_WAIT_RELEASE TIME_TO_WAIT_START 


if [[ !  "$GIT_NAME" == "$KGS_GITNAME" ]]; then 
  /egg_gitflow.sh $@
else
  /kgs_gitflow.sh $@
fi

