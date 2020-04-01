#!/bin/bash

if [ -z "$RANCHER_URL" ] || [ -z "$RANCHER_ACCESS" ] || [ -z "$RANCHER_SECRET" ] || [ -z "$RANCHER_ENVID" ] || [ -z "$RANCHER_URL" ] || [ -z "$stack_id" ] || [ -z "$template" ]; then
   echo "Did not receive all mandatory parameters!!!"
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
check=$(rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID stack | grep $stack_id)
current_catalog=$(echo $check | awk '{print $4}')
upgrade=$(echo $check | awk '{print $7}')
if [ "$current_catalog" == "catalog://EEA:$name:$number" ]; then echo "Stack already upgaded to the latest release"; exit 0; fi

count=0
while [ "$upgrade" != "$catalog:$number" ] && [ $count -lt 30 ]; do
    echo "Did not find stack to be upgrade-able yet, sleeping 1 min, then refreshing it again"
    sleep 60
    rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID catalog refresh | grep $catalog 
    let count=$count+1
    upgrade=$(rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID stack | grep $stack_id | awk '{print $7}')
done

if [ $count -eq 30 ]; then echo "30 minutes passed, stack is not upgrade-able, exiting"; exit 1; fi
echo "Found stack ready to be upgaded, upgrading stack to catalog://$catalog:$number"
rancher --url $RANCHER_URL --access-key $RANCHER_ACCESS --secret-key $RANCHER_SECRET --env $RANCHER_ENVID catalog upgrade catalog://$catalog:$number --stack $stack_id --confirm
