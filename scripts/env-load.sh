#!/usr/bin/env bash

base_env=$(find ./configs -name "base.env" -print)
cfg_dir=$(dirname "$(realpath "$base_env")")

final=$cfg_dir/final.env
rm -f "${final}"

# shellcheck disable=SC1090  # non-constant source: path determined at runtime
source "${base_env}"

{
  cat "$base_env"

  op run --env-file "${base_env}" -- \
  cat << EOF

# 1Password Entries
export OP_CONNECT_HOST="op://${OP_VAULT_HOMELAB}/${OP_CONNECT}/hostname"
export OP_SERVICE_ACCOUNT_TOKEN="op://${OP_VAULT_HOMELAB}/${OP_SERVICE_ACCT}/credential"
export OP_CONNECT_TOKEN="op://${OP_VAULT_HOMELAB}/${OP_CONNECT}/credential"
export OP_CLI_PATH=$([[ -e $(which op) ]] && which op || echo "/usr/local/bin/op")

# AI Models API Keys (Required to enable respective provider)
export ANTHROPIC_API_KEY="op://${OP_VAULT_DEV}/${OP_LLM_ANTHROPIC}/credentials/api_key"
export CLAUDE_CODE_AUTH_KEY="op://${OP_VAULT_DEV}/${OP_LLM_CLAUDE}/credentials/oauth_token"
export GOOGLE_API_KEY="op://${OP_VAULT_DEV}/${OP_LLM_GOOGLE}/credentials/api_key"
export PERPLEXITY_API_KEY="op://${OP_VAULT_DEV}/${OP_LLM_PERPLEXITY}/credentials/api_key"

# MCP Server API Keys
export CONTEXT7_API_KEY="op://${OP_VAULT_DEV}/${OP_MCP_CONTEXT7}/credentials/api_key"
export TODOIST_API_KEY="op://${OP_VAULT_DEV}/${OP_MCP_TODOIST}/credentials/api_key"

# Proxmox VE Credentials
export PROXMOX_VE_ENDPOINT="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/endpoint"
export PROXMOX_VE_USERNAME="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/id"
export PROXMOX_VE_API_TOKEN="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/token"
export PROXMOX_VE_PASSWORD="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/password"

# SSH Credentials for Proxmox VE
export PROXMOX_VE_SSH_USERNAME="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_SSH}/credentials/username"
export PROXMOX_VE_SSH_PASSWORD="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_SSH}/credentials/password"
export PROXMOX_VE_SSH_PRIVATE_KEY="op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_SSH}/private key?ssh-format=openssh"

export ANSIBLE_CONFIG=$(realpath "$(find . -name ansible.cfg)" | sort | head -n 1)
EOF

  cat << 'EOF'

# Terraform Variables for Proxmox VE
export TF_VAR_proxmox_ve_endpoint="${PROXMOX_VE_ENDPOINT}"
export TF_VAR_proxmox_ve_username="${PROXMOX_VE_USERNAME}"
export TF_VAR_proxmox_ve_token="${PROXMOX_VE_API_TOKEN}"
export TF_VAR_proxmox_ve_node_name="${PROXMOX_VE_NODE_NAME:-node-02}"
export TF_VAR_proxmox_ve_datastore_id="${PROXMOX_VE_DATASTORE_ID:-local-lvm}"
export TF_VAR_op_connect_host="${OP_CONNECT_HOST}"
export TF_VAR_op_connect_token="${OP_CONNECT_TOKEN}"
EOF
} >> "${final}"

if [ -e "${final}" ]; then
    echo "Final environment configuration generated at: ${final}"
    mv -v "$(dirname "${cfg_dir}")"/.env "$(dirname "${cfg_dir}")"/.env.bak 2>/dev/null || true
    cp -v "${final}" "$(dirname "${cfg_dir}")"/.env
else
    echo "Error: Failed to generate final environment configuration."
    exit 1
fi

alias init-env='cp -v .env .env.bak && op run --env-file .env --no-masking -- cat .env | op inject > .env.load && source .env.load && rm .env.load'
init-env() {
    cp -v .env .env.bak
    op run --env-file .env --no-masking -- cat .env | op inject > .env.load
    # shellcheck disable=SC1091  # .env.load generated at runtime
    source .env.load && rm .env.load
}
echo "Run alias command 'init-env' to source environment variables without 1password."
echo "   $(which init-env)"
