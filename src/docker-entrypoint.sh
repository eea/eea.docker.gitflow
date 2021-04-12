#!/bin/bash

set -e

export PYTHONIOENCODING=utf8


if [ -z "$GIT_NAME" ]; then
 echo "GIT repo name not given"
 exit 1
fi

GIT_ORG=${GIT_ORG:-'eea'}
GIT_USER=${GIT_USER:-'eea-jenkins'}
GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}

languages=$(curl -H "Accept: application/vnd.github.v3+json" -s  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/languages)


# for javascript repos
if [ $(curl  -Is  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/contents/package.json | grep -i http.*200 | wc -l) -eq 1 ] && [ -n "$GIT_TOKEN" ] && [ -n "$GIT_BRANCH" ] ; then
    #check language, if calculated
    if  [ $(echo $languages | grep : | wc -l) -eq 0 ] || [ $(echo $languages | grep -i javascript | wc -l) -ne 0 ]; then
    	exec /js-release.sh $@
    	exit 0
    fi
fi




GIT_SRC=https://github.com/${GIT_ORG}/${GIT_NAME}.git

if [ -z "$GIT_VERSIONFILE" ]; then
  GIT_VERSIONFILE="$(echo $GIT_NAME | sed 's|\.|/|g')/version.txt"
fi


GIT_HISTORYFILE=${GIT_HISTORYFILE:-'docs/HISTORY.txt'}
EGGREPO_URL=${EGGREPO_URL:-'https://eggrepo.eea.europa.eu/'}
PYPI_CHECK_URL=${PYPI_CHECK_URL:-'https://pypi.org/simple/'}
KGS_GITNAME=${KGS_GITNAME:-'eea.docker.kgs'}
WWW_GITNAME=${WWW_GITNAME:-'eea.docker.plone-eea-www'}
APACHE_GITNAME=${APACHE_GITNAME:-'eea.docker.apache-eea-www'}
VARNISH_GITNAME=${VARNISH_GITNAME:-'eea.docker.varnish-eea-www'}
KGS_VERSIONS_PATH=${KGS_VERSIONS_PATH:-'src/plone/versions.cfg'}
DOCKERHUB_KGSREPO=${DOCKERHUB_KGSREPO:-'eeacms/kgs'}
DOCKERHUB_WWWREPO=${DOCKERHUB_WWWREPO:-'eeacms/www'}
DOCKERHUB_WWWDEVREPO=${DOCKERHUB_WWWDEVREPO:-'eeacms/www-devel'}
DOCKERHUB_KGSDEVREPO=${DOCKERHUB_KGSDEVREPO:-'eeacms/kgs-devel'}
DOCKERHUB_APACHEREPO=${DOCKERHUB_APACHEREPO:-'eeacms/apache-eea-www'}
DOCKERHUB_VARNISHREPO=${DOCKERHUB_VARNISHREPO:-'eeacms/varnish-eea-www'}
RANCHER_CATALOG_GITNAME=${RANCHER_CATALOG_GITNAME:-'eea.rancher.catalog'}
DOCKERHUB_USER=${DOCKERHUB_USER:-'eeajenkins'}
EXTRACT_VERSION_SH=${EXTRACT_VERSION_SH:-'src/docker/calculate_next_release.sh'}


TIME_TO_WAIT_RELEASE=${TIME_TO_WAIT_RELEASE:-240}
TIME_TO_WAIT_START=${TIME_TO_WAIT_START:-30}


export GIT_ORG GIT_SRC GIT_VERSIONFILE GIT_HISTORYFILE GIT_USERNAME GIT_EMAIL EGGREPO_URL KGS_GITNAME KGS_VERSIONS_PATH APACHE_GITNAME VARNISH_GITNAME DOCKERHUB_KGSREPO DOCKERHUB_APACHEREPO DOCKERHUB_VARNISHREPO TIME_TO_WAIT_RELEASE TIME_TO_WAIT_START DOCKERHUB_WWWREPO DOCKERHUB_WWWDEVREPO DOCKERHUB_KGSDEVREPO WWW_GITNAME RANCHER_CATALOG_GITNAME PYPI_CHECK_URL DOCKERHUB_USER EXTRACT_VERSION_SH

export HOTFIX


if [[ "$GIT_NAME" == "$KGS_GITNAME" ]]; then
  exec /kgs_gitflow.sh $@
fi

if [[ "$GIT_NAME" == "$WWW_GITNAME" ]]; then
  exec /www_gitflow.sh $@
fi

if [[ "$GIT_NAME" == "$APACHE_GITNAME" ]]; then
    export DOCKERHUB_REPO=$DOCKERHUB_APACHEREPO    
    export RANCHER_CATALOG_SAME_VERSION=true
fi

if [[ "$GIT_NAME" == "$VARNISH_GITNAME" ]]; then
    export DOCKERHUB_REPO=$DOCKERHUB_VARNISHREPO
    export RANCHER_CATALOG_SAME_VERSION=true
fi

if [ -n "$DOCKERHUB_REPO" ]; then
    exec /gitflow.sh $@
else
    exec /egg_gitflow.sh $@
fi
