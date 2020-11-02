#!/bin/bash

#in case we are using old variable name
RANCHER_STACKID=${RANCHER_STACKID:-$stack_id}

if [ -z "$RANCHER_URL" ] || [ -z "$RANCHER_ACCESS" ] || [ -z "$RANCHER_SECRET" ]; then
   echo "Did not receive all mandatory parameters - url and auth!!!"
   exit 1
fi

if [ -z "$RANCHER_ENVID" ] || [ -z "$RANCHER_STACKID" ] || [ -z "$template" ]; then
   echo "Did not receive all mandatory parameters - rancher env, stack, template!!!"
   exit 1
fi

echo "Getting the latest catalog entry for $template"

rm -rf eea.rancher.catalog
git clone https://github.com/eea/eea.rancher.catalog.git
cd eea.rancher.catalog/$template
export number=$(find . -maxdepth 1 -type d | awk  'BEGIN{FS="/"}{print $2}' | sort -n | tail -n 1)
cd ..
rm -rf eea.rancher.catalog
echo  "Latest release catalog directory is $number"

name=$(echo $template | cut -d/ -f2)
catalog="EEA:$name"
echo "Refreshing rancher catalogs"
rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID catalog refresh | grep $catalog 
echo "Getting stack information"
check=$(rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID stack | grep $RANCHER_STACKID)
current_catalog=$(echo $check | awk '{print $4}')
upgrade=$(echo $check | awk '{print $7}')
if [ "$current_catalog" == "catalog://EEA:$name:$number" ]; then echo "Stack already upgraded to the latest release catalog://EEA:$name:$number"; exit 0; fi

count=0
while [[ "$check" != *"$catalog:$number"* ]] && [ $count -lt 30 ]; do
    if [ -z "$check" ]; then
         rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID stack
    fi
    echo "Did not find stack to be upgrade-able yet - '$check' is not *'$catalog:$number'*, sleeping 1 min, then refreshing it again"
    sleep 60
    rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID catalog refresh | grep $catalog 
    let count=$count+1
    check=$(rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID stack | grep $RANCHER_STACKID )
    echo "Stack information:"
    echo $check
done

if [ $count -eq 30 ]; then echo "30 minutes passed, stack is not upgrade-able, exiting"; exit 1; fi
echo "Found stack, it's ready to be upgraded to catalog://$catalog:$number"
rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID catalog upgrade catalog://$catalog:$number --stack $RANCHER_STACKID --confirm
