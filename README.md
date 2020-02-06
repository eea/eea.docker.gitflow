# eea.docker.gitflow
Used in jenkins to test github pull requests prerequisites and make releases.

## Pull request checks on eggs:

To run from jenkins:

> $docker run -i --name="$BUILD_TAG-gitflow-pr" -e GIT_BRANCH="$BRANCH_NAME" -e GIT_CHANGE_ID="$CHANGE_ID" -e GIT_CHANGE_AUTHOR="$CHANGE_AUTHOR" -e GIT_CHANGE_TITLE="$CHANGE_TITLE" -e GIT_TOKEN="$GITHUB_TOKEN" -e GIT_NAME="$GIT_NAME" eeacms/gitflow

### Variables
1. GIT_NAME - Mandatory, repository name, example: "eea.testegg"
2. GIT_ORG  - Organisation name, default: "eea"
3. GIT_VERSIONFILE - Location of the Versionfile, default: "eea/testegg/version.txt"
4. GIT_HISTORYFILE - Location of the changelog, default:"docs/HISTORY.txt"


### The checks:
1. History file updated in pull request
1. Version file updated in pull request
1. Version is not present in git tags
1. Version format is number.number
1. New version is bigger than last released version or no versions released yet


## Egg Release on commit to master

To run from jenkins:

> $docker run -i --name="$BUILD_TAG-gitflow-master" -e GIT_BRANCH="$BRANCH_NAME" -e EGGREPO_USERNAME="$EGGREPO_USERNAME" -e EGGREPO_PASSWORD="$EGGREPO_PASSWORD" -e GIT_NAME="$GIT_NAME"  -e PYPI_USERNAME="$PYPI_USERNAME"  -e PYPI_PASSWORD="$PYPI_PASSWORD" -e GIT_TOKEN="$GITHUB_TOKEN" eeacms/gitflow


### Variables
1. GIT_NAME - Mandatory, repository name, example: "eea.testegg"
2. GIT_ORG  - Organisation name, default: "eea"
3. GIT_VERSIONFILE - Location of the Versionfile, default: "eea/testegg/version.txt"
4. GIT_USERNAME - User that will do the changes in github, default "EEA Jenkins"
4. GIT_EMAIL - Email that will do the changes in github, default value set in code
1. EGGREPO_URL - URL of Repository for python eggs - default: https://eggrepo.eea.europa.eu/
1. KGS_GITNAME - Repository name on github for KGS (Docker image for Plone with EEA Common Add-ons) - default: eea.docker.kgs
1. KGS_VERSIONS_PATH - Location of file from KGS where the version of the egg is configured  - default: src/plone/versions.cfg


### Jenkins secret variables
1. EGGREPO_USERNAME, EGGREPO_PASSWORD - user and password for eggrepo
2. PYPI_USERNAME, PYPI_PASSWORD -  user and password for Pypi
3. GIT_TOKEN - token used for GitHub API


### The release steps:
1. Release on EGGREPO_URL
2. Create tag on GIT_NAME repo with released version
3. Update in KGS_GITNAME repo with the released version

> All the steps can be rerun, the job skipping the steps already processed	          	

## Plone release on commit to master

Is done only if there are files changed since the latest release. 

Updates local Dockerfiles(DEPENDENT_DOCKERFILE_URL) with the new release number.

Version is calculated using current date - `YY.MM.DD` ( when HOTFIX variable is given -  `YY.MM.DD-RELEASE`)  or using a script located at the `EXTRACT_VERSION_SH` variable value, which is by default `src/docker/calculate_next_release.sh`
Waits for dockerhub to finish the build succesfully before creating the Rancher Catalog release and triggering Dockerfile updates(DEPENDENT_DOCKERFILE_URL) and triggering Docker Hub repo builds (TRIGGER_RELEASE).

To run from jenkins:

> $docker run -i --rm --name="$BUILD_TAG-nightlyrelease" -e GIT_BRANCH="$BRANCH_NAME" -e GIT_ORG="$GIT_ORG" -e GIT_NAME="$GIT_NAME" -e DOCKERHUB_REPO="$DOCKERHUB_REPO" -e GIT_TOKEN="$GIT_TOKEN" -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  -e DEPENDENT_DOCKERFILE_URL="devel/Dockerfile ORG/REPO/blob/BRANCH/PATH_TO_Dockerfile"  -e TRIGGER_MAIN_URL="$TRIGGER_MAIN_URL" -e TRIGGER_RELEASE="DOCKERHUB_RELATED_REPO1;TRIGGER1 DOCKERHUB_RELATED_REPO2;TRIGGER2" eeacms/gitflow'


### Variables
1. GIT_NAME - Mandatory, repository name, example: "eea.docker.kgs"
2. GIT_ORG  - Organisation name, default: "eea"
4. GIT_USERNAME - User that will do the changes in github, default "EEA Jenkins"
4. GIT_EMAIL - Email that will do the changes in github, default value set in code
1. DOCKERHUB_REPO - Dockerhub repository name ( for example eeacms/kgs for KGS )
1. RANCHER_CATALOG_PATHS - If given will upgrade only the catalog paths after the release. If not given, will be calculated from the catalog locating all current releases containing `DOCKERHUB_REPO`
1. RANCHER_CATALOG_SAME_VERSION - If given, will not create new catalog releases, but upgrade the last one found in the catalog with the new release of `DOCKERHUB_REPO`
1. DEPENDENT_DOCKERFILE_URL - Space separated list of Dockerfiles witch will contain the new release of the `DOCKERHUB_REPO` - 2 types:
    * Local Dockerfile  - same branch, same repo, will share a release with the main Dockerfile so will be updated before the release on github - for example - devel/Dockerfile
    * Remote Dockerfile - other branch or other repo - format is - ORG/REPO/blob/BRANCH/PATH_TO_Dockerfile - will be updated after the release on Dockerhub and catalog
1. EXTRACT_VERSION_SH - location of script to calculate the next release, if file is not found will use the `YY.MM.DD` release.


### Jenkins secret variables
1. GIT_TOKEN - Mandatory, the token used for GitHub API
1. DOCKERHUB_USER - Mandatory, the token used for Dockerhub release trigger and check status 
1. DOCKERHUB_PASS - Mandatory, the token used for Dockerhub release trigger and check status
1. TRIGGER_MAIN_URL - Trigger url for DOCKERHUB_REPO to resubmit in case of failure to start
1. TRIGGER_RELEASE - Space separated list of DEPENDENT_DOCKERFILE_REPOS;TRIGGER_OF_THE_REPO - will be triggered after the DEPENDENT_DOCKERFILE_URL upgrades.


### EEA.DOCKER.PLONE release

> $docker run -i --rm --name="${BUILD_TAG}nightly-plone" -e GIT_BRANCH="master" -e GIT_NAME=""eea.docker.plone" -e DOCKERHUB_REPO="eeacms/plone" -e GIT_TOKEN="$GITHUB_TOKEN" -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  -e DEPENDENT_DOCKERFILE_URL="eea/eea.docker.plonesaas/blob/master/Dockerfile" eeacms/gitflow'

### EEA.DOCKER.PLONESAAS release

> $docker run -i --rm --name="${BUILD_TAG}nightly-plonesaas" -e GIT_BRANCH="master" -e GIT_NAME="eea.docker.plonesaas" -e DOCKERHUB_REPO="eeacms/plonesaas" -e GIT_TOKEN="$GIT_TOKEN" -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS" -e DEPENDENT_DOCKERFILE_URL="devel/Dockerfile" -e TRIGGER_MAIN_URL="xxx/trigger/xxx/call/" -e TRIGGER_RELEASE="eeacms/plonesaas-devel;yyy/trigger/yyy/call/" eeacms/gitflow'

### Apache/Varnish release on commit to master

To run from jenkins:

> $docker run -i --name="$BUILD_TAG-gitflow-master" -e GIT_BRANCH="$BRANCH_NAME" -e GIT_NAME=eea.docker.apache-eea-www  -e GIT_TOKEN="$GITHUB_TOKEN"  -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  eeacms/gitflow

and

> $docker run -i --name="$BUILD_TAG-gitflow-master" -e GIT_BRANCH="$BRANCH_NAME" -e GIT_NAME=eea.docker.varnish-eea-www  -e GIT_TOKEN="$GITHUB_TOKEN"  -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  eeacms/gitflow



