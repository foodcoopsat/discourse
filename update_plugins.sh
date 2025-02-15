#!/bin/bash
for name in assign calendar data-explorer docs reactions checklist solved;do
    latest_sha=$(curl -s https://api.github.com/repos/discourse/discourse-${name}/commits | jq -r '.[0].sha')
    name_upper=${name^^} 
    var_name=DISCOURSE_${name_upper//-/_}_VERSION
    echo "Update $var_name=$latest_sha"
    sed -i "s/^ENV ${var_name}=.*/ENV ${var_name}=${latest_sha}/g" Dockerfile
done
