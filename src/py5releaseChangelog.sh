#!/bin/bash

set -e

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to work"
   exit 1
fi

if [ -f /common_functions ]; then
    . /common_functions
elif [ -f ./common_functions ]; then
    . ./common_functions
fi


rm -f releasefile
touch releasefile


get_package_data()
{

package="$1"
new="$2"
old="$3"

echo "$package $old --> $new"

homepage=$(echo $curl_result | jq -r '.home_page' | sed 's/#.*$//' )


curl_result=$(curl -s "https://pypi.org/pypi/$package/json")

if [ $( echo $curl_result | grep -i "not found" |wc -l ) -eq 1 ]; then
        
	echo "Not found in pypi, checking in eggrepo"

	curl_result=$(curl -s -L "https://eggrepo.eea.europa.eu/d/$package")

	if [ $( echo $curl_result | grep -i "not found" | wc -l ) -eq 1 ]; then

		echo "Could not find home page from eggrepo and pypi"
                homepage=""
                type="undefined"
                return
	fi
	homepage=$(echo -e "$curl_result" | grep -A 1 "Home Page" | grep href | sed 's/.*href="\(.*\)">.*>/\1/')
	
	echo $curl_result | grep -A 1 "Home Page"  

	echo "Extracted homepage from eggrepo"


else

	homepage=$(echo $curl_result | jq -r '.info.home_page' | sed 's/#.*$//' )
        
	echo $homepage
	
	echo "Extracted homepage from pypi"

fi


echo "$package $old --> $new"

echo $homepage

if [ -z "$homepage" ] || [[ "$homepage" == "null" ]]; then
        echo "Not found homepage"
        homepage=""
        type="undefined"
        return
fi

if [[ ! "$homepage" == "https://github.com"* ]]; then
        echo "Homepage $homepage is not a github link"
        type="undefined"
        return
fi

if [ $(echo $homepage | grep "/eea/" | wc -l ) -eq 0 ]; then
    type="undefined"
    return
fi

if [ -z "$old" ]; then
    return
fi

temp=$old

if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//'  | tail -n 1) == "$new" ]]; then
    type="upgrade"
else
    type="downgrade"
    old=$new
    new=$old
fi

echo $type

url=$(echo "$homepage" | sed 's#/github.com/#/api.github.com/repos/#')"/releases?per_page=100"

valid_curl_get_result $url

echo $curl_result

versions=$( echo $curl_result | jq -r '.[].tag_name' | tac )

echo $versions

if [ $(echo -e "$versions" | wc -l) -eq 1 ] && [[ "$versions" == "$new" ]]; then
	echo "Found only one release, with the version $new"
	tags=$new
        return
fi

tags=$(echo -e "$versions" | awk "/^$old$/, /^$new$/" | tac | grep -v "^$temp$" || echo "" )

echo $tags

if [ -z "$tags" ]; then
        echo "Not found tags"
        type="undefined"
fi


}

get_release_by_tag()

{

repo="$1"
tag="$2"

url=$(echo "$repo" | sed 's#/github.com/#/api.github.com/repos/#')"/releases/tags/$tag"
echo $url

valid_curl_get_result $url
echo $curl_result
body=$(echo "$curl_result" | jq -r '.body' | sed 's/^#/###/')

}


get_release_docs()
{

	new_packages=$(diff  <(grep '=' new.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) <(grep '=' old.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) | grep "^< " | awk '{print $2}')
        old_packages=$(diff  <(grep '=' new.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) <(grep '=' old.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) | grep "^> " | awk '{print $2}')

       
	common=$(cat new.txt old.txt | grep "=" | grep -v '^#' | awk -F= '{print $1}' | sort | uniq -d)
	upgrade_packages=$(for i in $(echo "$common"); do new=$(grep ^$i new.txt | awk -F= '{print $2}'); old=$( grep ^$i old.txt | awk -F= '{print $2}'); if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1) == "$new"	]] && [[ ! "$new" == "$old" ]] ; then echo $i; fi; done)
	downgrade_packages=$(for i in $(echo "$common"); do new=$(grep ^$i new.txt | awk -F= '{print $2}'); old=$( grep ^$i old.txt | awk -F= '{print $2}'); if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1) == "$old"   ]] && [[ ! "$new" == "$old" ]]; then echo $i; fi; done)
        undefined_packages=""

        
	if [ -n "$upgrade_packages" ] || [ -n "$downgrade_packages" ] || [ -n "$new_packages" ] || [ -n "$old_packages" ]; then
	  echo -e "# Dependency updates\n" >> releasefile
        fi
	
	if [ -n "$upgrade_packages" ]; then

	for i in $(echo "$upgrade_packages"); do
            type="upgrade"
	    get_package_data $i $(grep ^$i new.txt | awk -F= '{print $2}') $(grep ^$i old.txt | awk -F= '{print $2}')
	    if [[ $type == "undefined" ]]; then
               echo -e "### [$i](https://pypi.org/project/$i/#changelog): $old ~ $new\n" >> releasefile
            else
	    
	    echo -e "### [$i]($homepage/releases): $old ~ $new\n" >> releasefile
	    for tag in $( echo "$tags"); do
                   get_release_by_tag $homepage $tag
		   echo "$body" >> releasefile
                   echo "" >> releasefile 
            done

	    fi
        done
	fi


        if [ -n "$downgrade_packages" ]; then 

	echo -e "## Downgrades \n" >> releasefile
        
        for i in $(echo "$downgrade_packages"); do
            type="downgrade"
	    nnew=$(grep ^$i new.txt | awk -F= '{print $2}')
	    nold=$(grep ^$i old.txt | awk -F= '{print $2}')
            get_package_data $i  $nnew  $nold
            if [[ $type == "undefined" ]]; then
                    echo -e "### [$i](https://pypi.org/project/$i/#changelog): $nold ~ $nnew\n" >> releasefile
            else
            echo -e "### [$i]($homepage/releases): $nold ~ $nnew\n" >> releasefile
	    for tag in $(echo "$tags"); do
                   get_release_by_tag $homepage $tag
                   echo "$body" >> releasefile
		   echo "" >> releasefile

            done
	    fi
        done
        fi


        if [ -n "$new_packages" ]; then

        echo -e "## New packages\n" >> releasefile

        for i in $(echo $new_packages); do
            type="new"
            get_package_data $i $(grep ^$i new.txt | awk -F= '{print $2}') 
            if [[ $type == "undefined" ]]; then
                    echo -e "### [$i](https://pypi.org/project/$i/#changelog): $new\n" >> releasefile
            else
                    echo -e "### [$i]($homepage): $new\n" >> releasefile
            fi

         done
         fi


        if [ -n "$old_packages" ]; then

        echo -e "## Removed packages\n" >> releasefile

        for i in $(echo $old_packages); do
            type="old"
            get_package_data $i $(grep ^$i old.txt | awk -F= '{print $2}')
            if [[ $type == "undefined" ]]; then
                    echo -e "### [$i](https://pypi.org/project/$i/#changelog): $new\n" >> releasefile
            else
                    echo -e "### [$i](https://pypi.org/project/$i/#changelog): $new\n" >> releasefile
            fi   
        done
         fi
 }


get_commits()
{
repo=$1
new_release=${2:-'master'}
old_release=$3

if [ -z "$old_release" ] && [[ $new_release == "master" ]]; then
valid_curl_get_result 	"https://api.github.com/repos/$repo/releases/latest"
old_release=$(echo "$curl_result" | jq -r ".name")

fi


VERSIONS_FILE=${VERSIONS_FILE:-'src/plone/versions.cfg'}


curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/${VERSIONS_FILE}?ref=$new_release" > new.txt
curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/${VERSIONS_FILE}?ref=$old_release" > old.txt

sed -i 's/[ ]*=[ ]*/=/g' new.txt old.txt




curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/Dockerfile?ref=$new_release" > newdocker
curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/Dockerfile?ref=$old_release" > olddocker

if [[ "$repo" == "eea/eea.docker.plone" ]]; then

ndocker=$(grep "^FROM" newdocker | awk -F':' '{print $2}' | tail -n 1)
odocker=$(grep "^FROM" olddocker | awk -F':' '{print $2}' | tail -n 1)

if [[ "$first_release" == "yes" ]]; then
   echo -e "# Plone\n" > releasefile
   echo -e "## Plone [$ndocker](https://plone.org/download/releases/$ndocker)" >> releasefile
else


if [[ ! "$ndocker" == "$odocker" ]];then

   echo -e "# Plone\n" > releasefile
   valid_curl_get_result https://api.github.com/repos/plone/Plone/tags?per_page=100

   versions=$(echo "$curl_result" | jq -r '.[].name' )

   bdocker=$(echo -e "$ndocker\n$odocker" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1)

   temp="$odocker"
   if [[ "$bdocker" == "$ndocker" ]]; then
	      echo -e "## Upgrade $odocker ~ $ndocker \n" >> releasefile

    else
	      echo -e "## Downgrade $odocker ~ $ndocker \n" >> releasefile
	      odocker="$ndocker"
	      ndocker="$temp"
   fi
   tags=$(echo -e "$versions" | awk "/^$ndocker$/, /^$odocker$/")


   for i in $(echo $tags); do
	   if [[ ! "$i" == "$temp" ]]; then
		   echo -e "* Plone [$i](https://plone.org/download/releases/$i)" >> releasefile
           fi
   done
   echo "" >> releasefile

fi
fi

else

ndocker=$(grep "FROM eeacms/plone" newdocker | awk -F':' '{print $2}' | tail -n 1)
odocker=$(grep "FROM eeacms/plone" olddocker | awk -F':' '{print $2}' | tail -n 1)

if [[ "$first_release" == "yes" ]]; then
   echo -e "# Plone\n" > releasefile

   echo -e "### eeacms/plone:[$ndocker](https://github.com/eea/eea.docker.plone/releases/tag/$ndocker)" >> releasefile
   curl_result=$(curl -X GET -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" -s "https://api.github.com/repos/eea/eea.docker.plone/releases/tags/$ndocker")
   body=$(echo $curl_result | jq -r '.body' | sed 's/^#/####/g'  )
   if [ -n "$body" ] && [[ ! "$body" == "null" ]]; then
       echo -e "$body" >> releasefile
   fi


else



if [[ ! "$ndocker" == "$odocker" ]];then

   echo -e "# Plone\n" > releasefile
   valid_curl_get_result https://api.github.com/repos/eea/eea.docker.plone/tags?per_page=100

   versions=$(echo "$curl_result" | jq -r '.[].name' )

   bdocker=$(echo -e "$ndocker\n$odocker" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1)

   temp="$odocker"

   if [[ "$bdocker" == "$ndocker" ]]; then
	   echo -e "## Upgrade [eeacms/plone](https://github.com/eea/eea.docker.plone): $odocker ~ $ndocker \n" >> releasefile

    else
	    echo -e "## Downgrade [eeacms/plone](https://github.com/eea/eea.docker.plone): $odocker ~ $ndocker \n" >> releasefile
              odocker="$ndocker"
              ndocker="$temp"
   fi
   tags=$(echo -e "$versions" | awk "/^$ndocker$/, /^$odocker$/")


   for i in $(echo $tags); do
           if [[ ! "$i" == "$temp" ]]; then
		   echo -e "### eeacms/plone:[$i](https://github.com/eea/eea.docker.plone/releases/tag/$i)" >> releasefile
		   curl_result=$(curl -X GET -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" -s "https://api.github.com/repos/eea/eea.docker.plone/releases/tags/$i")
		   body=$(echo $curl_result | jq -r '.body' | sed 's/^#/####/g'  )
		   if [ -n "$body" ] && [[ ! "$body" == "null" ]]; then
                       echo -e "$body" >> releasefile
		   fi

           fi
   done
   echo "" >> releasefile

fi

fi

fi



valid_curl_get_result "https://api.github.com/repos/$repo/compare/$old_release...$new_release"


echo "https://api.github.com/repos/$repo/compare/$old_release...$new_release"

echo $curl_result

commits=$(echo "$curl_result" | jq -r '.commits[] | select (.commit.author.name == "EEA Jenkins" | not ) | select (.commit.message | ( startswith("Merge pull request") or startswith("[JENKINS]")  ) | not )| "- \(.commit.message) - [\(.commit.author.name) -  [`\(.sha[0:7])`](\(.html_url))]"' )



echo "$commits"

get_release_docs

if [ -n "$commits" ] && [[ ! "$commits" == "null" ]]; then
  echo -e "# Internal\n" >> releasefile
  echo "$commits" |  sed 's/#\([0-9]\{5,6\}\)/\[#\1\]\(https:\/\/taskman.eionet.europa.eu\/issues\/\1\)/g'  >> releasefile
fi

}


repository="$1"
new_tag="$2"
old_tag="$3"

echo "Starting the extraction of the release documentation with parameters: $1 $2 $3"


if [ -z "$repository" ] && [ -n "$GIT_NAME" ]; then
	repository="$GIT_ORG/$GIT_NAME"
fi

if [ -z "$repository" ]; then
       echo "Please run the script with ./releaseChangelog.sh GIT_ORG/GIT_REPO release/branch old_release"
       echo "Default values are master for release/branch and latest release from master for old_release"
       echo "You can also run with 'export \$GIT_ORG/\$GIT_NAME; ./releaseChangelog.sh'"
       exit 1

fi

if [ -z "$new_tag" ]; then
	new_tag="master"
fi

if [ -z "$old_tag" ]; then

valid_curl_get_result "https://api.github.com/repos/$repository/releases?per_page=100" || echo "problem with releases github"

echo -e "$curl_result" > temp

if [[ "$new_tag" == "master" ]]; then
   old_tag=$(jq -r -n -f temp | jq -r '.[].tag_name' | head -n 1)
else
   old_tag=$(jq -r -n -f temp | jq -r '.[].tag_name' | grep -A 1 "^${new_tag}$" | grep -v "^${new_tag}$" || echo "")
fi

page=1

while [ -z "$old_tag" ] || [[ "$old_tag" == "null" ]]; do

  valid_curl_get_result "https://api.github.com/repos/$repository/commits?per_page=100&page=$page"
  old_tag=$(echo "$curl_result" | jq -r '.[] | select((.parents|length) == 0) | .sha')
  page=$((page+1))
  first_release="yes"
done



echo "Calculated old tag"

echo $old_tag 

fi


get_commits $repository $new_tag $old_tag


if [[ ! "$new_tag" == "master" ]]; then
valid_curl_get_result "https://api.github.com/repos/$repository/releases/tags/$new_tag"

id=$(echo "$curl_result" | jq -r ".id")

echo $curl_result  | jq --rawfile body releasefile '{"body": $body}' > body.json

curl -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" "https://api.github.com/repos/$repository/releases/$id" -d @body.json

fi
