#!/usr/bin/env bash

mapfile -t op_json < <(find . -name "*.op.json")

for file in "${op_json[@]}"; do
    echo "Configuring MCPs in $file"
    ofile="${file/.op/}"
    op inject -i "$file" -o "$ofile"
done

convert_to_json() {
    json_obj=$(
        grep -vE "#| (OP|PROXMOX|ANSIBLE|TF_VAR)_" .env \
        | sed 's/export /"/g' \
        | sed 's/=/":/g' \
        | sed 's/"$/",/g' \
        | op inject
        # | sed '/^$/d' \
    )
    printf "{\n%s}" "$json_obj"
}
get_mcp_env_vars() {
    grep -vE "#| (OP|PROXMOX|ANSIBLE|TF_VAR)_" .env \
    | sed 's/export //'
}
translate_keys() {
    # shellcheck disable=SC2154,SC2034,SC2068  # mcp_env_vars populated by caller; key unused (dead code)
    for index in "${!mcp_env_vars[@]}"; do
        key=$(echo "${mcp_env_vars[$index]}" | sed 's/="/ /;s/"$//')
        # for json in "${op_json[@]}"; do
        #     echo "Setting $key in $json"
        #     op inject -i "$json" -s "$key" "${mcp_env_vars[$index]}"
        # done
    done
}
