#!/bin/bash

set -e

git clone $GIT_SRC
cd $GIT_NAME


githubApiUrl="https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}"

source /common_functions


update_file()
{
 location=$1
 message=$2
 url="$githubApiUrl/contents/$location";

 curl_result=$( curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" $url?ref=${GIT_CHANGE_BRANCH} )
 if [ $( echo $curl_result | grep -c '"sha"' ) -eq 0 ]; then
      echo "There was a problem with the GitHub API request for $location:"
      echo $curl_result
      exit 1
 fi

 sha_file=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")
 echo "{\"message\": \"${message}\", \"sha\": \"${sha_file}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"branch\": \"${GIT_CHANGE_BRANCH}\", \"content\": \"$(printf '%s' $(cat $location | base64))\"}" > /tmp/curl_data

 result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data @/tmp/curl_data $url)
 if [ $(echo $result | grep -cE "HTTP/[0-9\.]* 200") -eq 1 ]; then
          echo "$location updated successfully"
   else
         echo "There was an error updating $location, please check the execution"
         echo $result
         exit 1
 fi
}

update_versionfile_withvalue()
{
 version=$1
 echo $version > $GIT_VERSIONFILE
 update_file $GIT_VERSIONFILE "Updated version to $version"
 echo "Version file updated to  $version"
}


update_versionfile()
{
 update_versionfile_withvalue $(echo $1 + 0.1 | bc)
}

if [ ! -z "$GIT_CHANGE_ID" ]; then
        GIT_BRANCH=PR-${GIT_CHANGE_ID}
        git fetch origin pull/$GIT_CHANGE_ID/head:$GIT_BRANCH
        files_changed=$(git --no-pager diff --name-only $GIT_BRANCH $(git merge-base $GIT_BRANCH master))


        git checkout $GIT_BRANCH
        if [ ! -f $GIT_VERSIONFILE ]; then
            GIT_VERSIONFILE="src/$GIT_VERSIONFILE"
        fi

        if [ $(echo $files_changed | grep $GIT_VERSIONFILE | wc -l) -eq 0 ]; then

             old_version=$(printf '%s' $(cat $GIT_VERSIONFILE))

             update_versionfile $old_version
             echo "Version file updated to default value ( last release +0.1), will stop execution "
             exit 0
        fi

        version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "Version is $version"
        echo "Passed check: Version file updated"


        git fetch --tags
        if [ $(git tag | grep -c "^$version$" ) -ne 0 ]; then
         echo "Version already present in tags, so will set it to default value - last release + 0.1"
         get_last_tag
         update_versionfile $latestTag
         exit 0
        fi

        echo "Passed check: Version is not present in git tags"

        if [[ ! $version  =~ ^[0-9]+\.[0-9]+$ ]] ; then

         if [[  $version  =~ ^[0-9]+\.[0-9]+[\.|-]dev[0-9]*$ ]] ; then
             new_version=$(echo $version | cut -d. -f1,2 | cut -d- -f1,1 )
             update_versionfile_withvalue $new_version
             echo "Removed dev from version file"
             exit 0
         fi


         echo "Version ${version} does not respect format: \"number.number\", so will set it to default value - last release + 0.1"
         get_last_tag
         update_versionfile $latestTag
         exit 0
        fi
        echo "Passed check: Version format is number.number"


        if [ $(git tag | wc -l) -eq 0 ]; then
             echo "Passed check: New version is bigger than last released version (no versions released yet)"
        else
                get_last_tag
                check_version_bigger=$(echo $version"."$latestTag | awk -F. '{if ($1 > $3 || ( $1 == $3 && $2 > $4) ) print "OK"}')

                if [[ ! $check_version_bigger == "OK" ]]; then
                 echo "Version ${version} is smaller than last version ${last_version}, will set it ${last_version} + 0.1"
                 update_versionfile $latestTag
                 exit 0
                fi
                echo "Passed check: New version is bigger than last released version"
        fi

        echo "Check if long_description_content_type exists in setup.py"

        if [ $(grep -c long_description_content_type setup.py) -eq 0 ]; then
                echo "Did not find long_description_content_type in setup.py, will add it to the default - RST"
                if [ -f README.rst ]; then
                        sed -i '/^      long_description=.*/i\      long_description_content_type='text/x-rst',' setup.py
                        update_file setup.py "Updated setup.py, added long_description_content_type - needs review"
                else
                        echo "Please add a long_description_content_type to setup.py, README.rst was not found"
                fi
        fi

        if [ $(grep -c "long_description_content_type=text/x-rst" setup.py) -eq 1 ]; then
                echo "Check HISTORYFILE rst format"
                if [ -f "$GIT_HISTORYFILE" ]; then
                        rstcheck $GIT_HISTORYFILE
                fi
                if [ -f "README.rst" ]; then
                        echo "Check README.rst format"
                        rstcheck README.rst
                fi
        fi



        if [ $(echo $files_changed | grep $GIT_HISTORYFILE | wc -l) -eq 0 ]; then
             echo "Changelog not updated, will populate it with default values"
             echo "Changelog
=========

$version - ($(date +"%Y-%m-%d"))
---------------------
* Change: $GIT_CHANGE_TITLE [$GIT_CHANGE_AUTHOR]
$(sed '1,2'd $GIT_HISTORYFILE)" > $GIT_HISTORYFILE

            update_file $GIT_HISTORYFILE "Updated changelog - needs review"

            echo "History file updated with default lines ( version, date and PR title  and user )"
            exit 0
        fi
        update_changelog=0
        if [ $(grep -c "(unreleased)"  $GIT_HISTORYFILE) -gt 0 ]; then
          sed -i "s/(unreleased)/($(date +"%Y-%m-%d"))/g" $GIT_HISTORYFILE
          echo "History file updated - replaced unreleased with date"
          update_changelog=1
        fi

        if [ $(grep -cE "^[0-9]+\.[0-9]+.dev[0-9]*" $GIT_HISTORYFILE) -gt 0 ]; then
           sed -i -r "s/(^[0-9]+\.[0-9]+).dev[0-9]*/\1/" $GIT_HISTORYFILE
           echo "History file updated -  removed dev version"
           update_changelog=1
        fi

        if [ $update_changelog -eq 1 ]; then
           update_file $GIT_HISTORYFILE "Updated changelog - removed develop information"
           echo "History file updated -  removed dev version"
           exit 0
        fi

        echo "Passed check: History file updated"


        echo "Passed all checks"
fi


if [[ "$GIT_BRANCH" == "master" ]]; then

        #check if release already exists
        if [ ! -f $GIT_VERSIONFILE ]; then
            GIT_VERSIONFILE="src/$GIT_VERSIONFILE"
        fi
        version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "--------------------------------------------------------------------------------------------------------------------"

        if [ ! -z "$EGGREPO_USERNAME$EGGREPO_PASSWORD" ]; then

          echo "Checking if version is released on EGGREPO"
          egg_releases=$(curl -s -i "${EGGREPO_URL}d/${GIT_NAME,,}/")


          if [ $(echo "$egg_releases" | grep -Ec "HTTP/[0-9\.]* (200|404)") -eq 0 ]; then
             echo "There was a problem with the EGG repository - HTTP response code not 200 or 404"
             echo "Please check ${EGGREPO_URL}d/${GIT_NAME,,}/"
             echo "$egg_releases"
             exit 1
          fi

          if [ $(echo "$egg_releases" | grep -cE "HTTP/[0-9\.]* 404") -eq 1 ] || [ $(echo "$egg_releases" | grep -c ">${GIT_NAME}-${version}.zip<") -ne 1 ]; then
              
              echo "Starting the release ${GIT_NAME}-${version}.zip on EEA repo"
              python setup.py sdist --formats=zip
              twine upload -u ${EGGREPO_USERNAME} -p ${EGGREPO_PASSWORD} --repository-url ${EGGREPO_URL} dist/*
              twine register -u ${EGGREPO_USERNAME} -p ${EGGREPO_PASSWORD} --repository-url ${EGGREPO_URL} dist/*
              echo "Release ${GIT_NAME}-${version}.zip done on ${EGGREPO_URL}"

         else
             echo "Release ${GIT_NAME}-${version}.zip already exists on EEA repo, skipping"
          fi
          echo "--------------------------------------------------------------------------------------------------------------------"
        fi

        if [ ! -z "$PYPI_USERNAME$PYPI_PASSWORD" ]; then
          echo "Checking if version is released on PyPi"

          pypi_releases=$(curl -i -sL "${PYPI_CHECK_URL}${GIT_NAME}/")


          if [ $(echo "$pypi_releases" | grep -Ec "HTTP/[0-9\.]* (200|404)") -eq 0 ]; then
             echo "There was a problem with the PIPY repository - HTTP response code not 200 or 404"
             echo "Please check ${PYPI_CHECK_URL}${GIT_NAME}/"
             echo "$pypi_releases"
             exit 1
          fi

          if [ $(echo "$pypi_releases" | grep -cE "HTTP/[0-9\.]* 404") -eq 1 ]; then
            echo "Egg will not be released on PyPi because it does not have any releases - ${PYPI_CHECK_URL}${GIT_NAME}/"
          else

            if [ $(echo "$pypi_releases" | grep -c ">${GIT_NAME}-${version}.zip<") -ne 1 ]; then
               echo "Starting the release ${GIT_NAME}-${version}.zip on PyPi repo"
               if [ ! -f dist/${GIT_NAME}-${version}.zip ];then
		       python setup.py sdist --formats=zip
	       fi
	       twine upload -u ${PYPI_USERNAME} -p ${PYPI_PASSWORD} dist/*
               echo "Release ${GIT_NAME}-${version}.zip  done on PyPi"
            else
              echo "Release ${GIT_NAME}-${version}.zip already exists on PyPi repo, skipping"
            fi
          fi
          echo "--------------------------------------------------------------------------------------------------------------------"
        fi

        #check if tag exiss
        if [ $(git tag | grep -c "^$version$") -eq 0 ]; then
         echo "Starting the creation of the tag $version on master"

         curl_result=$(curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"Release $version\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

         if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
            echo "There was a problem with the release"
            echo $curl_result
            exit 1
         fi

         echo "Release $version succesfully created"

        else
          echo "Tag $version already created, skipping"
        fi

        echo "--------------------------------------------------------------------------------------------------------------------"


        GITHUBURL=${githubApiUrl}/git

        curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "${githubApiUrl}/contents/${GIT_VERSIONFILE}?ref=develop"  > ${GIT_VERSIONFILE}

        if [ $(grep -c ^$version$ ${GIT_VERSIONFILE}) -eq 1 ]; then
        echo "Found same version on develop as just released, will update it"

        curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "${githubApiUrl}/contents/${GIT_HISTORYFILE}?ref=develop"  > ${GIT_HISTORYFILE}

        next_version=$( echo "$(echo $version + 0.1 | bc)-dev0")
        echo $next_version  > $GIT_VERSIONFILE
        echo "Changelog
=========

$next_version - (unreleased)
---------------------
$(sed '1,2'd $GIT_HISTORYFILE)" > $GIT_HISTORYFILE

       valid_curl_get_result ${GITHUBURL}/refs/heads/develop sha
       sha_develop=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['object']['sha']")

       valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat ${GIT_VERSIONFILE} | base64))\",\"encoding\": \"base64\" }" sha
       sha_version=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


       valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat ${GIT_HISTORYFILE} | base64))\",\"encoding\": \"base64\" }" sha
       sha_history=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

       valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_develop}\",\"tree\": [{\"path\": \"${GIT_VERSIONFILE}\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_version}\" }, { \"path\": \"${GIT_HISTORYFILE}\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_history}\" }]}" sha

       sha_newtree=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

       # create commit

       valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Back to devel\", \"parents\": [\"${sha_develop}\"], \"tree\": \"${sha_newtree}\"}"  sha

       sha_new_commit=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")


       # update branch to commit
       curl_result=$(curl -i -s -X PATCH -H "Authorization: bearer $GIT_TOKEN" --data " { \"sha\":\"$sha_new_commit\"}" ${GITHUBURL}/refs/heads/develop)

       if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 200" ) -eq 0 ]; then
              echo "There was a problem with the commit on develop"
              echo $curl_result
              exit 1
        fi

      else
       echo "Version file already changed on develop"
      fi


        echo "--------------------------------------------------------------------------------------------------------------------"

    if [ ! -z "$EGGREPO_PASSWORD$PYPI_PASSWORD" ]; then
      # Updating versions.cfg
      echo "Starting the update of KGS versions.cfg"
      curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}"  > versions.cfg

      if [ $(grep -c "\[versions\]" versions.cfg) -eq 0 ]; then
        echo "There was a problem getting the versions file"
        cat versions.cfg
        exit 1
      fi

      if [ $(grep -c "^${GIT_NAME} = $version$" versions.cfg) -eq 1 ]; then
          echo "KGS versions file already updated, skipping"
      else
        old_version=$( grep  "^${GIT_NAME} =" versions.cfg | awk '{print $3}')

        check_version_bigger=$(echo $version"."$old_version | awk -F. '{if ($1 > $3 || ( $1 == $3 && $2 > $4) ) print "OK"}')

        if [[ ! $check_version_bigger == "OK" ]]; then
          echo "${version} is smaller than the version from ${KGS_GITNAME} - ${old_version}, skipping"
        else

          echo "Updating KGS versions file with released version"

          curl_result=$( curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}" )

          if [ $( echo $curl_result | grep -c '"sha"' ) -eq 0 ]; then
             echo "There was a problem with the GitHub API request:"
             echo $curl_result
             exit 1
          fi


          sha_versionfile=$(echo $curl_result |  python -c "import sys, json; print json.load(sys.stdin)['sha']")

          grep -q "^${GIT_NAME} =" versions.cfg  && sed -i "s/^${GIT_NAME} =.*/${GIT_NAME} = $version/" versions.cfg || sed -i "/# automatically set /a ${GIT_NAME} = $version" versions.cfg

          result=$(curl -i -s -X PUT -H "Authorization: bearer $GIT_TOKEN" --data "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_versionfile}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat versions.cfg | base64))\"}" "https://api.github.com/repos/${GIT_ORG}/${KGS_GITNAME}/contents/${KGS_VERSIONS_PATH}")

          if [ $(echo $result | grep -cE "HTTP/[0-9\.]* 200") -eq 1 ]; then
             echo "KGS versions file updated succesfully"
          else
             echo "There was an error updating the KGS file, please check the execution"
             echo $result
             exit 1
          fi
       fi
    fi
 fi

fi


exec "$@"

