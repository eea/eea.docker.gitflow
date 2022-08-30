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


rm -f releasefile

get_package_data()
{

package="$1"
new="$2"
old="${3:-'0.0'}"

echo "$package $old --> $new"

homepage=$(echo $curl_result | jq -r '.home_page' | sed 's/#.*$//' )


curl_result=$(curl -s "https://pypi.org/pypi/$package/json")

if [ $( echo $curl_result | grep -i "not found" |wc -l ) -eq 1 ]; then

	curl_result=$(curl -s "https://eggrepo.eea.europa.eu/d/$package")

	if [ $( echo $curl_result | grep -i "not found" | wc -l ) -eq 1 ]; then

		echo "Could not find home page from eggrepo and pypi"
                homepage=""
                type="undefined"
                return
	fi
	homepage=$(echo $curl_result | grep -A 1 "Home Page" | grep href | sed 's/.*href="\(.*\)">.*>/\1/')
	echo "Extracted homepage from eggrepo"


else

	homepage=$(echo $curl_result | jq -r '.info.home_page' | sed 's/#.*$//' )
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




if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//'  | tail -n 1) == "$new" ]]; then
    type="upgrade"
else
    type="downgrade"
    temp=$new
    new=$old
    old=$temp
fi

echo $type

url=$(echo "$homepage" | sed 's#/github.com/#/api.github.com/repos/#')"/releases?per_page=100"

if [ $(echo $homepage | grep "/eea/" | wc -l ) -eq 0 ]; then
    type="undefined"
    return
fi
valid_curl_get_result $url


versions=$( echo $curl_result | jq -r '.[].tag_name' | tac )

echo $versions

tags=$(echo -e "$versions" | awk "/^$old$/, /^$new$/" | tac | tail -n +2 )

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

	new_packages=$(diff  <(grep '==' new.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) <(grep '==' old.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) | grep "^< " | awk '{print $2}')
        old_packages=$(diff  <(grep '==' new.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) <(grep '==' old.txt | grep -v '^#' | awk -F= '{print $1}' | sort ) | grep "^> " | awk '{print $2}')

       
	common=$(cat new.txt old.txt | grep "==" | grep -v '^#' | awk -F= '{print $1}' | sort | uniq -d)
	upgrade_packages=$(for i in $(echo "$common"); do new=$(grep ^$i new.txt | awk -F== '{print $2}'); old=$( grep ^$i old.txt | awk -F== '{print $2}'); if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1) == "$new"	]] && [[ ! "$new" == "$old" ]] ; then echo $i; fi; done)
	downgrade_packages=$(for i in $(echo "$common"); do new=$(grep ^$i new.txt | awk -F== '{print $2}'); old=$( grep ^$i old.txt | awk -F== '{print $2}'); if [[ $(echo -e "$new\n$old" | sed '/-/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -n 1) == "$old"   ]] && [[ ! "$new" == "$old" ]]; then echo $i; fi; done)
        undefined_packages=""

        echo -e "# Constraints updates\n" > releasefile

	
	if [ -n "$upgrade_packages" ]; then
        echo -e "## Upgrades \n" >> releasefile

	for i in $(echo "$upgrade_packages"); do
	    get_package_data $i $(grep ^$i new.txt | awk -F== '{print $2}') $(grep ^$i old.txt | awk -F== '{print $2}')
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

            get_package_data $i $(grep ^$i new.txt | awk -F== '{print $2}') $(grep ^$i old.txt | awk -F== '{print $2}')
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

        echo -e "## Others \n" >> releasefile

        for i in $(echo $undefined_packages); do

            get_package_data $i $(grep ^$i new.txt | awk -F== '{print $2}') $(grep ^$i old.txt | awk -F== '{print $2}')
	    if [ -n "$homepage" ]; then
		    echo -e "### [$i]($homepage): $old ~ $new\n" >> releasefile
	    else
	            echo -e "### [$i](https://pypi.org/project/$i/): $old ~ $new\n" >> releasefile
	    fi
        done
       fi

        if [ -n "$new_packages" ]; then

        echo -e "## New packages\n" >> releasefile

        for i in $(echo $new_packages); do

            get_package_data $i $(grep ^$i new.txt | awk -F== '{print $2}') 
            if [ -n "$homepage" ]; then
                    echo -e "### [$i]($homepage): $new\n" >> releasefile
            else
                    echo -e "### [$i](https://pypi.org/project/$i/): $new\n" >> releasefile
            fi

         done
         fi


        if [ -n "$old_packages" ]; then

        echo -e "## Removed packages\n" >> releasefile

        for i in $(echo $old_packages); do

            get_package_data $i $(grep ^$i old.txt | awk -F== '{print $2}') 
            echo -e "### $i: $old\n" >> releasefile
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


commits=$(echo "$curl_result" | jq -r '.commits[] | select (.commit.author.name == "EEA Jenkins" | not ) | select (.commit.message | ( startswith("Merge pull request") or startswith("[JENKINS]")  ) | not )| "- \(.commit.message) - [\(.commit.author.name) -  [`\(.sha[0:7])`](\(.html_url))]"' )



echo "$commits"

curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/constraints.txt?ref=$new_release" > new.txt
curl -s -X GET  -H "Authorization: bearer $GIT_TOKEN"  -H "Accept: application/vnd.github.VERSION.raw" "https://api.github.com/repos/$repo/contents/constraints.txt?ref=$old_release" > old.txt

get_release_docs

if [ -n "$commits" ] && [[ ! "$commits" == "null" ]]; then
  echo -e "# Internal\n" >> releasefile
  echo "$commits" >> releasefile
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


get_commits $repository $new_tag $old_tag


#if [[ ! "$new_tag" == "master" ]]; then
#valid_curl_get_result "https://api.github.com/repos/$repository/releases/tags/$new_tag"

#id=$(echo "$curl_result" | jq -r ".id")

#echo $curl_result  | jq --rawfile body releasefile '{"body": $body}' > body.json

#curl -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token $GIT_TOKEN" "https://api.github.com/repos/$repository/releases/$id" -d @body.json

#fi
