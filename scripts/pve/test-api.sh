#!/usr/bin/env bash

user=${1:-${PROXMOX_VE_USERNAME:-SET_USER}}
token_value=${2:-${PROXMOX_VE_API_TOKEN:-SET_TOKEN}}
realm=${3:${PROXMOX_VE_USER_REALM:-pve}}
token_name=${4:${PROXMOX_VE_TOKEN_NAME:-provider}}
# shellcheck disable=SC2034  # used in the commented curl line below
endpoint=${5:-${PROXMOX_VE_ENDPOINT:-localhost}}

echo "Authorization: PVEAPIToken=${user}@${realm}!${token_name}=${token_value}" https://node-02.homelab.ts.net:8006/api2/json/nodes | jq
#curl -k -H 'Content-Type: application/json' -H "Authorization: PVEAPIToken=${user}@${realm}!${token_name}=${token_value}" https://node-02.homelab.ts.net:8006/api2/json/nodes | jq

