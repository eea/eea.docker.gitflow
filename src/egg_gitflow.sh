#!/bin/bash

set -e

git clone $GIT_SRC
cd $GIT_NAME


githubApiUrl="https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}"

. /common_functions


update_file()
{
 location=$1
 message=$2
 url="$githubApiUrl/contents/$location";

 valid_curl_get_result "$url?ref=${GIT_CHANGE_BRANCH}" sha

 sha_file=$(echo $curl_result |  jq -r '.sha // empty')
 
 valid_curl_put_result $url "{\"message\": \"${message}\", \"sha\": \"${sha_file}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"branch\": \"${GIT_CHANGE_BRANCH}\", \"content\": \"$(printf '%s' $(cat $location | base64))\"}"

 echo "$location updated successfully"
}


create_file()
{
 location=$1
 message=$2
 url="$githubApiUrl/contents/$location";

 valid_curl_put_result $url "{\"message\": \"${message}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"branch\": \"${GIT_CHANGE_BRANCH}\", \"content\": \"$(printf '%s' $(cat $location | base64))\"}"

 echo "$location created successfully"
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
 update_versionfile_withvalue $(echo $1 | awk '{printf "%.1f-dev0", $1 + 0.1}' )
}


calculate_version() 
{ 
 echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; 
}

update_plone_config()
{
PLONE_GITNAME=$1
VERSIONS_PATH=$2
EGG_NAME=${GIT_NAME}
BRANCH_NAME=master

if [ -n "$3" ]; then
    BRANCH_NAME=$3
fi
    

echo "Starting the update of $PLONE_GITNAME $VERSIONS_PATH, on branch $BRANCH_NAME"

curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}?ref=${BRANCH_NAME}"  > versions.cfg


if [ $(grep -c "\[versions\]" versions.cfg) -eq 0 ]; then
   echo "There was a problem getting the versions file"
   cat versions.cfg
   exit 1
fi

if [ $(grep -c "^${EGG_NAME} =" versions.cfg) -eq 0 ]; then
  EGG_NAME=$(echo ${GIT_NAME} | sed 's/_/-/')
  if [ $(grep -c "^${EGG_NAME} =" versions.cfg) -eq 0 ]; then
    echo "Could not find ${GIT_NAME} release in ${PLONE_GITNAME} in ${VERSIONS_PATH} on branch $BRANCH_NAME, skipping upgrade"
    return
  fi
fi

if [ $(grep -E "DISABLE auto-release:.*${EGG_NAME}[ ]*$" versions.cfg | wc -l) -gt 0 ]; then
  echo "Found this line in versions.cfg:"
  grep -E -n "DISABLE auto-release.*${EGG_NAME}[ ]*$" versions.cfg
  echo "Will not update the version of egg ${EGG_NAME} as auto-release is disabled"
  return
fi

if [ $(grep -c "^${EGG_NAME} = $version$" versions.cfg) -eq 1 ]; then
    echo "${PLONE_GITNAME} versions file already updated with '${EGG_NAME} = $version' on branch $BRANCH_NAME, skipping"
    return
fi

old_version=$( grep  "^${EGG_NAME} =" versions.cfg | awk '{print $3}')
if [ $(calculate_version $version) -gt $(calculate_version $old_version) ]; then 
   check_version_bigger="OK"
fi
   
if [[ "${old_version}" == "${version}-dev"* ]]; then 
      check_version_bigger="OK"
fi

if [[ ! $check_version_bigger == "OK" ]]; then
      echo "${version} is smaller than the version from ${PLONE_GITNAME} - ${old_version}, skipping"
      return
fi
echo "Updating ${PLONE_GITNAME} versions file on branch $BRANCH_NAME with released version on ${EGG_NAME}"

valid_curl_get_result "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}?ref=${BRANCH_NAME}" sha

sha_versionfile=$(echo $curl_result |  jq -r '.sha // empty')

sed -i "s/^${EGG_NAME} =.*/${EGG_NAME} = $version/" versions.cfg 

valid_curl_put_result "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}" "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_versionfile}\",\"branch\": \"${BRANCH_NAME}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat versions.cfg | base64))\"}" 

echo "${PLONE_GITNAME} versions file on branch $BRANCH_NAME updated succesfully with '${EGG_NAME} = $version'"

}

update_plone_constraints()
{
PLONE_GITNAME=$1
VERSIONS_PATH=$2
EGG_NAME=${GIT_NAME}
BRANCH_NAME=master

if [ -n "$3" ]; then
    BRANCH_NAME=$3
fi
    

echo "Starting the update of $PLONE_GITNAME $VERSIONS_PATH, on branch $BRANCH_NAME"

curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}?ref=${BRANCH_NAME}"  > constraints.txt


if [ $(grep -c "==" constraints.txt) -eq 0 ] && [ $(grep -c eggrepo constraints.txt) -eq 0 ]; then
   echo "There was a problem getting the constraints file"
   cat constraints.txt
   exit 1
fi

if [ $(grep -c "^${EGG_NAME}==" constraints.txt) -eq 0 ]; then
  EGG_NAME=$(echo ${GIT_NAME} | sed 's/_/-/')
  if [ $(grep -c "^${EGG_NAME}==" constraints.txt) -eq 0 ]; then
    echo "Could not find ${GIT_NAME} release in ${PLONE_GITNAME} in ${VERSIONS_PATH} on branch $BRANCH_NAME, skipping upgrade"
    return
  fi
fi

if [ $(grep -c "^${EGG_NAME}==$version$" constraints.txt) -eq 1 ]; then
    echo "${PLONE_GITNAME} versions file already updated with '${EGG_NAME} = $version' on branch $BRANCH_NAME, skipping"
    return
fi

old_version=$( grep  "^${EGG_NAME}==" constraints.txt | awk -F='=' '{print $2}')
if [ $(calculate_version $version) -gt $(calculate_version $old_version) ]; then 
   check_version_bigger="OK"
fi
   
if [[ "${old_version}" == "${version}-dev"* ]]; then 
      check_version_bigger="OK"
fi

if [[ ! $check_version_bigger == "OK" ]]; then
      echo "${version} is smaller than the version from ${PLONE_GITNAME} - ${old_version}, skipping"
      return
fi
echo "Updating ${PLONE_GITNAME} contstraints file on branch $BRANCH_NAME with released version on ${EGG_NAME}"

valid_curl_get_result "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}?ref=${BRANCH_NAME}" sha

sha_versionfile=$(echo $curl_result |  jq -r '.sha // empty')

sed -i "s/^${EGG_NAME}==.*/${EGG_NAME}==$version/" constraints.txt

valid_curl_put_result "https://api.github.com/repos/${GIT_ORG}/${PLONE_GITNAME}/contents/${VERSIONS_PATH}" "{\"message\": \"Release ${GIT_NAME} $version\", \"sha\": \"${sha_versionfile}\",\"branch\": \"${BRANCH_NAME}\", \"committer\": { \"name\": \"${GIT_USERNAME}\", \"email\": \"${GIT_EMAIL}\" }, \"content\": \"$(printf '%s' $(cat constraints.txt | base64))\"}" 

echo "${PLONE_GITNAME} contstraints file on branch $BRANCH_NAME updated succesfully with '${EGG_NAME}==$version'"

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
             echo "Files changed: $files_changed"
	     echo "Version file: $GIT_VERSIONFILE"
	     echo "Did not find version file changed"
             old_version=$(printf '%s' $(cat $GIT_VERSIONFILE))
	     
	     git fetch --tags
             if [ $(git tag | grep -c "^$old_version$" ) -ne 0 ]; then
               update_versionfile $old_version
               echo "Version file updated to default value ( last release +0.1), will stop execution "
               #exit 0
	     else
	       echo "Did not find version $old_version in tags, will keep the same version as in in master, as it is unreleased"
             fi
        fi

        version=$(printf '%s' $(cat $GIT_VERSIONFILE))
        echo "Version is $version"
        echo "Passed check: Version file updated"


        git fetch --tags
        if [ $(git tag | grep -c "^$version$" ) -ne 0 ]; then
         echo "Version already present in tags, so will set it to default value - last release + 0.1"
         get_last_tag
         update_versionfile $latestTag
         echo "Fixed check: Version is not present in git tags"
         #exit 0
	else
         echo "Passed check: Version is not present in git tags"
	fi
     
        if [[ ! $version  =~ ^[0-9]+\.[0-9]+$ ]] ; then

         if [[  $version  =~ ^[0-9]+\.[0-9]+[\.|-]dev[0-9]*$ ]] ; then
             new_version=$(echo $version | cut -d. -f1,2 | cut -d- -f1,1 )
	     echo "Version format from version.txt is not ok, will set it to $new_version"
             update_versionfile_withvalue $new_version
             echo "Removed dev from version file"
             #exit 0
         else
           echo "Version ${version} does not respect format: \"number.number\", so will set it to default value - last release + 0.1"
           get_last_tag
           update_versionfile $latestTag
           echo "Fixed check: Version format is number.number"
           #exit 0
	 fi
	else
	   echo "Passed check: Version format is number.number"
        fi

	

        if [ $(git tag | wc -l) -eq 0 ]; then
             echo "Passed check: New version is bigger than last released version (no versions released yet)"
        else
                get_last_tag
                biggest_version=$(echo "$version
$latestTag" | sort --sort=version | tail -n 1 )

                if [[ $bigger_version == "$latestTag" ]]; then
                 echo "Version ${version} is smaller than last version ${latestTag}, will set it ${latestTag} + 0.1"
                 update_versionfile $latestTag
                 echo "Fixed check: New version is bigger than last released version"
                 #exit 0
	        else
                  echo "Passed check: New version is bigger than last released version"

		fi
        fi

        echo "Check if long_description_content_type exists in setup.py"

        if [ $(grep -c long_description_content_type setup.py) -eq 0 ]; then
                echo "Did not find long_description_content_type in setup.py, will add it to the default - RST"
                if [ -f README.rst ]; then
		        cp setup.py /tmp/setup.py
                        new_line=$(grep '^ *long_description=.*' setup.py | sed 's#long_description=.*#long_description_content_type="text/x-rst",#')
                        sed -i "/^ *long_description=.*/i\\${new_line}" setup.py
			if [ $(diff setup.py /tmp/setup.py | wc -l) -gt 0 ]; then
                           update_file setup.py "Updated setup.py, added long_description_content_type - needs review"
			else
			   echo "There is a problem with your setup.py, check that it has long_description, long_description_content_type and description values"
			   exit 1
			fi   
                else
                        echo "Please add a long_description_content_type to setup.py, README.rst was not found"
                fi
        fi

   

        if [ $(grep -c 'long_description_content_type=.*text/x-rst.*' setup.py) -eq 1 ]; then
                echo "Check HISTORYFILE rst format"
                if [ -f "$GIT_HISTORYFILE" ]; then
                        # fix "Title underline too short" 
			if [ $( grep -c "^---------------------$"  "$GIT_HISTORYFILE" ) -gt 0 ]; then
				sed -i "s/^---------------------$/--------------------------/g" "$GIT_HISTORYFILE" 
				echo "Fixed short title underlines"
                                update_file $GIT_HISTORYFILE "Fixed short title underlines in changelog"
				#exit 0
			fi



                        rstcheck --report-level warning $GIT_HISTORYFILE
                fi
                if [ -f "README.rst" ]; then
                        echo "Check README.rst format"
                        rstcheck --report-level warning README.rst
                fi
                echo "Passed check: README.rst and $GIT_HISTORYFILE have correct RST format"
	fi

	namespace=$(echo $GIT_VERSIONFILE |  cut -d'/' -f1)
	if [ -f MANIFEST.in ]; then
          	echo "Checking MANIFEST.in file and fixing it"

                if [ $( grep -c "include.*txt.*"   MANIFEST.in ) -eq 0 ] || [ $( grep -c "graft docs"   MANIFEST.in ) -eq 0 ] || [ $( grep -c "graft $namespace"   MANIFEST.in ) -eq 0 ]; then
			echo "Did not find correct MANIFEST.in file, will re-set it to default value"
			echo "include *.md *.rst *.txt
graft docs
graft ${namespace}
global-exclude *pyc
global-exclude *~
global-exclude *.un~
global-include *.mo" > MANIFEST.in
                       update_file MANIFEST.in "Updated MANIFEST.in, recreated it from template using $namespace - needs review"
		fi
                echo "Passed check: MANIFEST.in contains docs and files"
	else
	        echo "include *.md *.rst *.txt
graft docs
graft ${namespace}
global-exclude *pyc
global-exclude *~
global-exclude *.un~
global-include *.mo" > MANIFEST.in
                 create_file MANIFEST.in "Created MANIFEST.in from template using $namespace - needs review"
		 #exit 0
	fi

        if [ $(echo $files_changed | grep $GIT_HISTORYFILE | wc -l) -eq 0 ]; then
             echo "Did not find $GIT_HISTORYFILE in the files changed in the PR:"
	     echo "$files_changed"	
	     if [ $( grep -cE "^$version -.*" $GIT_HISTORYFILE ) -eq 0 ]; then
	       echo "Did not find $version entry in  $GIT_HISTORYFILE, will populate it with default values"
               echo "Changelog
=========

$version - ($(date +"%Y-%m-%d"))
---------------------------
* Change: $GIT_CHANGE_TITLE [$GIT_CHANGE_AUTHOR]
$(sed '1,2'd $GIT_HISTORYFILE)" > $GIT_HISTORYFILE

              update_file $GIT_HISTORYFILE "Updated changelog - needs review"

              echo "History file updated with default lines ( version, date and PR title  and user )"
              #exit 0
	    else
	      echo "Found $version entry in  $GIT_HISTORYFILE, so will skip updating it "
	    fi
        fi


        update_changelog=0
        
	if [ $( awk '/unreleased/,/\*/' $GIT_HISTORYFILE | grep -c '^--*$') -eq 2 ]; then
          line_nr=$(grep -n unreleased $GIT_HISTORYFILE | head -n 1 | awk -F':' '{print $1}')
          let line_nr=line_nr+2
	  sed -i "${line_nr}i* Change: $GIT_CHANGE_TITLE"  $GIT_HISTORYFILE
          let line_nr=line_nr+1	  
	  sed -i "${line_nr}i\  [$GIT_CHANGE_AUTHOR]"  $GIT_HISTORYFILE
	  
          echo "History file updated - added Pull request title and author after unreleased"
	  update_changelog=1
        fi

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
           #exit 0
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

        if [[ "$version" == *"-dev"* ]]; then 
	      echo "Version file not updated, still contains -dev, error" 
	      exit 1
	fi

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

          if [ $(echo "$egg_releases" | grep -E "HTTP/[0-9\.]* 404" | wc -l ) -eq 1 ] || [ $(echo $egg_releases | grep -cE ">${GIT_NAME}-${version}\.tar\.gz<|>${GIT_NAME}-${version}\.zip<" ) -ne 1 ]; then

              echo "Compiling po files to mo"
              pocompile

              echo "Starting the release ${GIT_NAME}-${version}.tar.gz on EEA repo"
              python setup.py sdist --formats=gztar
              twine register -u ${EGGREPO_USERNAME} -p ${EGGREPO_PASSWORD} --repository-url ${EGGREPO_URL} dist/*
              twine upload -u ${EGGREPO_USERNAME} -p ${EGGREPO_PASSWORD} --repository-url ${EGGREPO_URL} dist/*
              echo "Release ${GIT_NAME}-${version} done on ${EGGREPO_URL}"

         else
             echo "Release ${GIT_NAME}-${version} already exists on EEA repo, skipping"
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

            if [ $(echo $egg_releases | grep -cE ">${GIT_NAME}-${version}\.tar\.gz<|>${GIT_NAME}-${version}\.zip<") -ne 1 ]; then
               echo "Starting the release ${GIT_NAME}-${version}.tar.gz on PyPi repo"
               if [ ! -f dist/${GIT_NAME}-${version}.tar.gz ];then
		       python setup.py sdist --formats=gztar
	       fi
	       twine upload -u ${PYPI_USERNAME} -p ${PYPI_PASSWORD} dist/*
               echo "Release ${GIT_NAME}-${version}.tar.gz  done on PyPi"
            else
              echo "Release ${GIT_NAME}-${version} already exists on PyPi repo, skipping"
            fi
          fi
          echo "--------------------------------------------------------------------------------------------------------------------"
        fi

        #check if tag exiss
        if [ $(git tag | grep -c "^$version$") -eq 0 ]; then
         echo "Starting the creation of the tag $version on master"
         export GIT_HISTORYFILE

	 /extractChangelog.sh $version
         body=$(cat releasefile | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed 's/"/\\\"/g' )


	 echo "Will release with body: $body"

         curl_result=$(curl -i -s -X POST -H "Authorization: bearer $GIT_TOKEN" --data "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"$body\", \"draft\": false, \"prerelease\": false }"   https://api.github.com/repos/${GIT_ORG}/${GIT_NAME}/releases )

         if [ $( echo $curl_result | grep -cE "HTTP/[0-9\.]* 201" ) -eq 0 ]; then
            echo "There was a problem with the release"
	    echo "{\"tag_name\": \"$version\", \"target_commitish\": \"master\", \"name\": \"$version\", \"body\":  \"$body\", \"draft\": false, \"prerelease\": false }" 
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
          
          next_version=$( echo $version | awk '{printf "%.1f-dev0", $1 + 0.1}' )
          echo $next_version  > $GIT_VERSIONFILE
          echo "Changelog
=========

$next_version - (unreleased)
---------------------------
$(sed '1,2'd $GIT_HISTORYFILE)" > $GIT_HISTORYFILE

         valid_curl_get_result ${GITHUBURL}/refs/heads/develop object.sha
	 sha_develop=$(echo $curl_result |  jq -r '.object.sha // empty' )

         valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat ${GIT_VERSIONFILE} | base64))\",\"encoding\": \"base64\" }" sha
         sha_version=$(echo $curl_result |  jq -r '.sha // empty')


         valid_curl_post_result ${GITHUBURL}/blobs "{\"content\": \"$(printf '%s' $(cat ${GIT_HISTORYFILE} | base64))\",\"encoding\": \"base64\" }" sha
         sha_history=$(echo $curl_result |  jq -r '.sha // empty')

         valid_curl_post_result  ${GITHUBURL}/trees "{\"base_tree\": \"${sha_develop}\",\"tree\": [{\"path\": \"${GIT_VERSIONFILE}\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_version}\" }, { \"path\": \"${GIT_HISTORYFILE}\", \"mode\": \"100644\", \"type\": \"blob\", \"sha\": \"${sha_history}\" }]}" sha

         sha_newtree=$(echo $curl_result |  jq -r '.sha // empty')

         # create commit

         valid_curl_post_result   ${GITHUBURL}/commits "{\"message\": \"Back to devel\", \"parents\": [\"${sha_develop}\"], \"tree\": \"${sha_newtree}\"}"  sha

         sha_new_commit=$(echo $curl_result |  jq -r '.sha // empty')


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
    
      if [[ "$GIT_NAME" == "Products.Reportek" ]]; then
        update_plone_config eea.docker.reportek.base-dr-instance src/versions.cfg testing
	#there is no need to check other plones
        exit 0
      fi
      
      # Updating versions.cfg
      update_plone_config ${KGS_GITNAME} ${KGS_VERSIONS_PATH} master
      update_plone_config eea.docker.plone src/plone/versions.cfg master
      update_plone_config eea.docker.plonesaas src/plone/versions.cfg master
      update_plone_config marine-backend site.cfg develop
      
      #Updating constraints.txt - Nightly release from master
      update_plone_constraints plone-backend constraints.txt master
      update_plone_constraints eea-website-backend constraints.txt master
      update_plone_constraints advisory-board-backend constraints.txt master
      update_plone_constraints clms-backend constraints.txt master
      update_plone_constraints insitu-backend constraints.txt master
      update_plone_constraints fise-backend constraints.txt master
      update_plone_constraints ied-backend constraints.txt master
      update_plone_constraints freshwater-backend constraints.txt master

      #Updating constraints.txt - PR to master from develop
      update_plone_constraints bise-backend constraints.txt develop

    fi
fi

exec "$@"


