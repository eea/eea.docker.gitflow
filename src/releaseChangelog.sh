#!/bin/bash

set -e

if [ -z "$GIT_TOKEN" ]; then
   echo "Need GIT_TOKEN environment variable to work"
   exit 1
fi

if [ -f /common_functions ]; then
    source /common_functions
elif [ -f ./common_functions ]; then
    source ./common_functions
fi




get_package_data()
{

package="$1"
new="$2"
old="${3:-'0.0.0'}"

curl_result=$(curl -s "https://registry.npmjs.org/$package")
echo "$package $old --> $new"

homepage=$(echo $curl_result | jq -r '.homepage' | sed 's/#.*$//' )

if [ -z "$homepage" ] || [[ "$homepage" == "null" ]] || [[ ! "$homepage" == "https://github.com"* ]]; then
        echo "Extracting from repository"
        homepage=$(echo $curl_result | jq -r '.repository.url' | sed 's#git+ssh://git@#https://#' | sed 's#\.git##' )

fi

echo $homepage
if [ -z "$homepage" ] || [[ "$homepage" == "null" ]]; then
        echo "Not found homepage"
        homepage=""
        type="undefined"
        return
fi

if [ $(echo $new | grep -E '^[0-9]+\.[0-9]+\.[0-9]+.*' | wc -l) -eq 0 ] || [ $(echo $old | grep -E '^[0-9]+\.[0-9]+\.[0-9]+.*' | wc -l) -eq 0 ]; then
    echo "Not ok $new or $old version"
    type="undefined"
    return
fi    


if [[ $(echo -e "$new\n$old" | sort -V | tail -n 1) == "$new" ]]; then
    type="upgrade"
else
    type="downgrade"
    temp=$new
    new=$old
    old=$temp
fi

echo $type

versions=$( echo $curl_result | jq -r '.versions[].version' | sort -V )

echo $versions

tags=$(echo -e "$versions" | awk "/^$old$/, /^$new$/" | tail -n +2 )

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

	new_packages=$(diff  <(jq '.dependencies | keys[]' new.json | sort ) <(jq '.dependencies | keys[]' old.json | sort) | grep "^< " | awk -F'"' '{print $2}')
        old_packages=$(diff  <(jq '.dependencies | keys[]' new.json | sort ) <(jq '.dependencies | keys[]' old.json | sort) | grep "^> " | awk -F'"' '{print $2}')
	common=$(jq -r '.dependencies | keys[]' new.json old.json | sort | uniq -d)
	upgrade_packages=$(for i in $(echo "$common"); do new=$(jq -r ".dependencies[\"$i\"]" new.json); old=$(jq -r ".dependencies[\"$i\"]" old.json); if [[ $(echo -e "$new\n$old" | sort -V | tail -n 1) == "$new"	]] && [[ ! "$new" == "$old" ]] ; then echo $i; fi; done)
	downgrade_packages=$(for i in $(echo "$common"); do new=$(jq -r ".dependencies[\"$i\"]" new.json); old=$(jq -r ".dependencies[\"$i\"]" old.json); if [[ $(echo -e "$new\n$old" | sort -V | tail -n 1) == "$old"   ]] && [[ ! "$new" == "$old" ]]; then echo $i; fi; done)
        undefined_packages=""

        echo -e "# Dependency updates\n" > releasefile

	
	if [ -n "$upgrade_packages" ]; then
        echo -e "## Upgrades \n" >> releasefile

	for i in $(echo "$upgrade_packages"); do
            get_package_data $i $(jq -r ".dependencies[\"$i\"]" new.json) $(jq -r ".dependencies[\"$i\"]" old.json)
	    if [[ $type == "undefined" ]]; then
                  echo "skipping $i"
		  undefined_packages="$undefined_packages $i"
		  continue
	    fi

	    echo -e "### [$i: $old ~ $new]($homepage/releases)\n" >> releasefile
	    for tag in $( echo "$tags"); do
                   get_release_by_tag $homepage $tag
		   echo "$body" >> releasefile
                   echo "" >> releasefile 
            done
        done
	fi

        if [ -n "$downgrade_packages" ]; then 

	echo -e "## Downgrades \n" >> releasefile
        
        for i in $(echo "$downgrade_packages"); do

            get_package_data $i $(jq -r ".dependencies[\"$i\"]" new.json) $(jq -r ".dependencies[\"$i\"]" old.json)
            if [[ $type == "undefined" ]]; then
                  continue
            fi
            echo -e "### [$i: $new ~ $old]($homepage/releases)\n" >> releasefile
	    for tag in $(echo "$tags"); do
                   get_release_by_tag $homepage $tag
                   echo "$body" >> releasefile
		   echo "" >> releasefile

            done
        done
        fi

       if [ -n "$undefined_packages" ]; then

        echo -e "## Undefined \n" >> releasefile

        for i in $(echo $undefined_packages); do

            get_package_data $i $(jq -r ".dependencies[\"$i\"]" new.json) $(jq -r ".dependencies[\"$i\"]" old.json)
	    echo -e "### [$i](https://www.npmjs.com/package/$i): $old ~ $new\n" >> releasefile
        done
       fi

        if [ -n "$new_packages" ]; then

        echo -e "## New packages\n" >> releasefile

        for i in $(echo $new_packages); do

            get_package_data $i $(jq -r ".dependencies[\"$i\"]" new.json) 
	    echo -e "### [$i]($homepage/tree/$new): $new\n" >> releasefile
        done
         fi


        if [ -n "$old_packages" ]; then

        echo "## Removed packages\n" >> releasefile

        for i in $(echo $old_packages); do

            get_package_data $i $(jq -r ".dependencies[\"$i\"]" old.json)
            echo "### $i: $old\n" >> releasefile
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

valid_curl_get_result "https://api.github.com/repos/$repo/compare/$old_release...$new_release"

commits=$(echo "$curl_result" | jq -r '.commits[] | select (.commit.author.name == "EEA Jenkins" | not ) | select (.commit.message | ( startswith("Merge pull request") or startswith("[JENKINS]")  ) | not )| "- \(.commit.message) - [`\(.sha[0:8])`](\(.html_url))"' )



echo "$commits"

curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/package.json?ref=$new_release" > new.json
curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/package.json?ref=$old_release" > old.json

get_release_docs

if [ -n "$commits" ] && [[ ! "$commits" == "null" ]]; then
  echo -e "# Internal\n" >> releasefile
  echo "$commits" >> releasefile
fi

}


#repository=eea/eea-website-frontend
#volto-eea-kitkat
#new_tag=0.18.0
#old_tag=0.17.0

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


get_commits $repository $new_tag $old_tag

if [[ ! "$new_tag" == "master" ]]; then
valid_curl_get_result "https://api.github.com/repos/$repository/releases/tags/$new_tag"

id=$(echo "$curl_result" | jq -r ".id")

echo $curl_result  | jq --rawfile body releasefile '{"body": $body}' > body.json

curl -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" "https://api.github.com/repos/$repository/releases/$id" -d @body.json

fi
