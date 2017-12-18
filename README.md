# eea.docker.gitflow
Used in jenkins to test github pull requests prerequisites and make releases.

## Pull request checks:

To run from jenkins:

> $docker run -i --name="$BUILD_TAG-gitflow-pr" -e GIT_BRANCH="$BRANCH_NAME" -e GIT_CHANGE_ID="$CHANGE_ID" -e GIT_ORG="$GIT_ORG" -e GIT_VERSIONFILE="$GIT_VERSIONFILE" -e GIT_HISTORYFILE="$GIT_HISTORYFILE" -e GIT_NAME="$GIT_NAME" eeacms/gitflow

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


## Release on commit to master

To run from jenkins:

> $docker run -i --name="$BUILD_TAG-gitflow-master" -e GIT_BRANCH="$BRANCH_NAME" -e EGGREPO_USERNAME="$EGGREPO_USERNAME" -e EGGREPO_PASSWORD="$EGGREPO_PASSWORD" -e GIT_NAME="$GIT_NAME" -e GIT_VERSIONFILE="$GIT_VERSIONFILE" -e GIT_ORG="$GIT_ORG" -e GIT_TOKEN="$GITHUB_TOKEN" eeacms/gitflow


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
2. GIT_TOKEN - token used for GitHub API

### The release steps:
1. Release on EGGREPO_URL
2. Create tag on GIT_NAME repo with released version
3. Update in KGS_GITNAME repo with the released version

> All the steps can be rerun, the job skipping the steps already processed	          	

