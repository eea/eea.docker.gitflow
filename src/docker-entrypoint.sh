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

if [ -z "$PYPI_URL" ]; then
 PYPI_URL=https://pypi.python.org/pypi
fi

if [  -z "$PYPI_CHECK_URL" ]; then
 PYPI_CHECK_URL=https://pypi.python.org/simple/
fi

if [ -z "$KGS_GITNAME" ]; then
  KGS_GITNAME=eea.docker.kgs
fi

if [ -z "$WWW_GITNAME" ]; then
  WWW_GITNAME=eea.docker.plone-eea-www
fi

if [ -z "$KGS_VERSIONS_PATH" ]; then
  KGS_VERSIONS_PATH=src/plone/versions.cfg
fi

if [ -z "$DOCKERHUB_KGSREPO" ]; then
  DOCKERHUB_KGSREPO="eeacms/kgs"
fi

if [ -z "$DOCKERHUB_WWWREPO" ]; then
  DOCKERHUB_WWWREPO="eeacms/www"
fi

if [ -z "$DOCKERHUB_WWWDEVREPO" ]; then
  DOCKERHUB_WWWDEVREPO="eeacms/www-devel"
fi

if [ -z "$DOCKERHUB_KGSDEVREPO" ]; then
  DOCKERHUB_KGSDEVREPO="eeacms/kgs-devel"
fi


if [ -z "$TIME_TO_WAIT_RELEASE" ]; then
  TIME_TO_WAIT_RELEASE=240
fi

if [ -z "$TIME_TO_WAIT_START" ]; then
  TIME_TO_WAIT_START=30
fi

if [ -z "$RANCHER_CATALOR_GITNAME" ]; then
  RANCHER_CATALOR_GITNAME=eea.rancher.catalog
fi

export GIT_ORG GIT_SRC GIT_VERSIONFILE GIT_HISTORYFILE GIT_USERNAME GIT_EMAIL EGGREPO_URL KGS_GITNAME KGS_VERSIONS_PATH DOCKERHUB_KGSREPO TIME_TO_WAIT_RELEASE TIME_TO_WAIT_START DOCKERHUB_WWWREPO DOCKERHUB_WWWDEVREPO DOCKERHUB_KGSDEVREPO WWW_GITNAME RANCHER_CATALOR_GITNAME PYPI_URL PYPI_CHECK_URL

export HOTFIX


if [[ "$GIT_NAME" == "$KGS_GITNAME" ]]; then
  exec /kgs_gitflow.sh $@
fi

if [[ "$GIT_NAME" == "$WWW_GITNAME" ]]; then
  exec /www_gitflow.sh $@
fi

exec /egg_gitflow.sh $@

