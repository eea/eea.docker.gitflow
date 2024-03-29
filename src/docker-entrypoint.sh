#!/bin/bash

set -e

export PYTHONIOENCODING=utf8

export GIT_ORG=${GIT_ORG:-'eea'}
export GIT_USER=${GIT_USER:-'eea-jenkins'}
export GIT_USERNAME=${GIT_USERNAME:-'EEA Jenkins'}
export GIT_EMAIL=${GIT_EMAIL:-'eea-jenkins@users.noreply.github.com'}
export CI=${CI:-'yes'}




if [[ "$1" == *".sh" ]] || [[ "$1" == "/"* ]] || [[ "$1" == "./"* ]] ; then
	if [ -f "$1" ]; then
	    echo "> Found script $1 as argument, will now run it"
	    exec $@
	fi
fi


if [ -z "$GIT_NAME" ]; then
 echo "GIT repo name not given"
 exit 1
fi


if [[ "$LANGUAGE" == "javascript" ]]; then

	if [[ ! "${GIT_NAME,,}" =~ ^.*frontend$ ]] && [[ ! "${GIT_NAME,,}" =~ ^.*storybook$ ]]; then
		exec /js-release.sh $@
	else
		exec /frontend-release.sh $@
	fi
fi

languages=$(curl -H "Accept: application/vnd.github.v3+json" -s  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/languages)

# for javascript repos
if [ ! $(curl  -Is  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/contents/package.json | grep -i http.*404 | wc -l) -eq 1 ] && [ -n "$GIT_TOKEN" ] && [ -n "$GIT_BRANCH" ] && [[ ! "$GITFLOW_BEHAVIOR" == "RUN_ON_TAG" ]]; then

    if [[ "${GIT_NAME,,}" =~ ^.*frontend$ ]]; then
                exec /frontend-release.sh $@
    fi

    #check language, if calculated, check if not python - setup.py, check if not docker - Dockerfile
    if  [ $(echo $languages | grep : | wc -l) -eq 0 ] || [ $(echo $languages | grep -i javascript | wc -l) -ne 0 ] && [ $(curl  -Is  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/contents/setup.py | grep -i http.*200 | wc -l) -eq 0 ] && [ $(curl  -Is  https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/contents/Dockerfile | grep -i http.*200 | wc -l) -eq 0 ]; then
    	exec /js-release.sh $@
    fi
fi

GIT_SRC=https://github.com/${GIT_ORG}/${GIT_NAME}.git

if [ -z "$GIT_VERSIONFILE" ]; then
  GIT_VERSIONFILE="$(echo $GIT_NAME | sed 's|\.|/|g')/version.txt"
fi


export GIT_HISTORYFILE=${GIT_HISTORYFILE:-'docs/HISTORY.txt'}
export EGGREPO_URL=${EGGREPO_URL:-'https://eggrepo.eea.europa.eu/'}
export PYPI_CHECK_URL=${PYPI_CHECK_URL:-'https://pypi.org/simple/'}
export KGS_GITNAME=${KGS_GITNAME:-'eea.docker.kgs'}
export WWW_GITNAME=${WWW_GITNAME:-'eea.docker.plone-eea-www'}
export APACHE_GITNAME=${APACHE_GITNAME:-'eea.docker.apache-eea-www'}
export VARNISH_GITNAME=${VARNISH_GITNAME:-'eea.docker.varnish-eea-www'}
export KGS_VERSIONS_PATH=${KGS_VERSIONS_PATH:-'src/plone/versions.cfg'}
export DOCKERHUB_KGSREPO=${DOCKERHUB_KGSREPO:-'eeacms/kgs'}
export DOCKERHUB_WWWREPO=${DOCKERHUB_WWWREPO:-'eeacms/www'}
export DOCKERHUB_WWWDEVREPO=${DOCKERHUB_WWWDEVREPO:-'eeacms/www-devel'}
export DOCKERHUB_KGSDEVREPO=${DOCKERHUB_KGSDEVREPO:-'eeacms/kgs-devel'}
export DOCKERHUB_APACHEREPO=${DOCKERHUB_APACHEREPO:-'eeacms/apache-eea-www'}
export DOCKERHUB_VARNISHREPO=${DOCKERHUB_VARNISHREPO:-'eeacms/varnish-eea-www'}
export RANCHER_CATALOG_GITNAME=${RANCHER_CATALOG_GITNAME:-'eea.rancher.catalog'}
export DOCKERHUB_USER=${DOCKERHUB_USER:-'eeajenkins'}
export EXTRACT_VERSION_SH=${EXTRACT_VERSION_SH:-'src/docker/calculate_next_release.sh'}


export TIME_TO_WAIT_RELEASE=${TIME_TO_WAIT_RELEASE:-240}
export TIME_TO_WAIT_START=${TIME_TO_WAIT_START:-30}


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
