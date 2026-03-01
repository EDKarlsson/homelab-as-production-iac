#!/usr/bin/env bash

base_env=$( find ./configs -name "base.env" -print)
env_files=(
    $(find ./configs/templates -name "*.env" -print) 
)
combined=configs/gen/combined.env
final=configs/gen/final.env
rm ${combined} ${final} 2>/dev/null || true

source ${base_env}

echo "# Base Environment Variables" >> "${combined}"
cat "${base_env}" >> "${combined}"
for env_file in "${env_files[@]}"; do
    target_file="${env_file}"
    printf "\n#%s\n" "${target_file}" >> "${combined}"
    file_content=$(cat "${target_file}")
    file_content=$(sed '/PROXMOX_VE_SSH_PRIVATE_KEY/d' <<< "${file_content}")
    echo "${file_content}" >> "${combined}"
done

op run --env-file ${base_env} -- cat "${combined}" | op inject > "${final}"