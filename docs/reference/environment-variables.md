---
title: Environment Variable Architecture
description: How environment variables and secrets flow through the homelab-iac project including env files, secrets management, and credential flow
published: true
date: 2026-02-18
tags:
  - environment
  - secrets
  - 1password
  - terraform
  - ansible
  - configuration
---

How environment variables and secrets flow through the homelab-iac project. This covers every env file, its purpose, what is tracked vs gitignored, and the critical gotchas learned from production debugging.

## Design Principles

1. **No plaintext secrets in git.** Every file containing real credentials is gitignored.
2. **1Password is the single source of truth.** Terraform reads credentials from 1Password Connect at plan/apply time. The Connect JWT token is the only secret that must exist in the local environment.
3. **`op://` references for everything else.** AI keys, MCP tokens, and other secrets use `op://` URIs resolved at runtime by the 1Password CLI (`op run`).
4. **`PROXMOX_VE_*` env vars must never be set.** The bpg/proxmox Terraform provider auto-reads these from the environment and they silently override the provider block configuration. All Proxmox auth flows through 1Password Connect.

## File Overview

```
homelab-iac/
  .env.example              # [tracked]    Template with placeholders for new setup
  .env.d/
    terraform.env           # [gitignored] Source before terraform commands
    base.env                # [gitignored] General tooling (Ansible, SSH, Todoist)
  configs/
    base.env                # [tracked]    Non-secret 1Password UUIDs for scripts
    final.env               # [gitignored] Full environment using op:// references
```

### Tracked vs Gitignored Summary

| File | Tracked | Contains Secrets | Usage |
|------|---------|-----------------|-------|
| `.env.example` | Yes | No (placeholders) | Template for new setup |
| `configs/base.env` | Yes | No (UUIDs only) | 1Password item references for scripts |
| `.env.d/terraform.env` | No | Yes (Connect JWT, PG password via `op`) | Source before `terraform` commands |
| `.env.d/base.env` | No | Yes (Todoist API key) | Source for general tooling |
| `configs/final.env` | No | No (op:// URIs, resolved at runtime) | Use with `op run --env-file` |

## File Details

### `.env.d/terraform.env` -- Terraform Session Environment

**Purpose:** The minimum environment needed to run `terraform plan` and `terraform apply`.

**Usage:**
```bash
source .env.d/terraform.env
terraform plan
```

**Contents:**

| Variable | Purpose | Secret? |
|----------|---------|---------|
| `TF_VAR_op_connect_host` | 1Password Connect VIP (`http://10.0.0.72:8080`) | No |
| `TF_VAR_op_connect_token` | Connect JWT token | Yes |
| `PG_CONN_STR` | PostgreSQL backend connection string | Yes (password embedded) |
| `TF_VAR_proxmox_ve_datastore_id` | Default datastore (`local-lvm`) | No |
| `TF_VAR_proxmox_ve_node_name` | Default PVE node (`node-02`) | No |

**How it works:** The `TF_VAR_` prefix causes Terraform to automatically bind these to the corresponding variables in `infrastructure/variables.tf`. The 1Password provider uses `op_connect_host` and `op_connect_token` to connect to the self-hosted Connect server, then reads all other credentials (Proxmox, SSH keys, K3s tokens) from 1Password at plan/apply time.

**PG_CONN_STR detail:** The PostgreSQL backend connection string uses a shell subcommand to fetch the database password from 1Password at source time:

```bash
export PG_CONN_STR="postgres://terraform:$(env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get homelab-k3s-cluster --vault Homelab --fields database.password --reveal 2>/dev/null)@10.0.0.45:5432/terraform_state"
```

The `env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN` prefix is critical -- it strips the Connect environment variables from the subshell so the `op` CLI does not attempt Connect auth mode (which conflicts with interactive/service-account auth). See [Gotcha: 1Password auth modes are mutually exclusive](#1password-auth-modes-are-mutually-exclusive).

### `.env.d/base.env` -- General Tooling

**Purpose:** Environment for Ansible, SSH, and other non-Terraform tools.

**Usage:**
```bash
source .env.d/base.env
ansible-playbook ...
```

**Contents:**

| Variable | Purpose |
|----------|---------|
| `ANSIBLE_CONFIG` | Path to `ansible.cfg` in the repo |
| `TODOIST_API_KEY` | Todoist integration token |
| `SSH_AUTH_SOCK` | 1Password SSH agent socket (`~/.1password/agent.sock`) |

**Note on SSH_AUTH_SOCK:** Setting this to the 1Password agent socket means all SSH connections (including Ansible, `terraform apply` via the bpg/proxmox SSH provisioner, and manual `ssh` commands) use keys managed by 1Password. No disk-based private keys are needed.

### `configs/base.env` -- 1Password UUIDs (Tracked)

**Purpose:** Non-secret 1Password vault and item UUIDs used by scripts and tooling that need to reference specific 1Password items programmatically.

**Usage:**
```bash
source configs/base.env
op item get "$OP_PROXMOX_TF" --vault "$OP_VAULT_HOMELAB" --fields credentials.password --reveal
```

**Contents:**

| Variable | Value Type | Purpose |
|----------|-----------|---------|
| `OP_VAULT_HOMELAB` | UUID | Homelab vault identifier |
| `OP_VAULT_DEV` | UUID | Dev vault identifier |
| `OP_SERVICE_ACCT` | UUID | Service account item |
| `OP_CONNECT` | UUID | Connect server item |
| `OP_PROXMOX_TF` | UUID | Proxmox Terraform credentials item |
| `OP_PROXMOX_SSH` | UUID | Proxmox SSH key item |
| `OP_LLM_ANTHROPIC` | UUID | Anthropic API key item |
| `OP_LLM_CLAUDE` | UUID | Claude Code auth item |
| `OP_LLM_GOOGLE` | UUID | Google AI API key item |
| `OP_LLM_PERPLEXITY` | UUID | Perplexity API key item |
| `OP_MCP_CONTEXT7` | UUID | Context7 MCP key item |
| `OP_MCP_TODOIST` | UUID | Todoist MCP key item |

**Why this is safe to commit:** UUIDs are opaque identifiers. They cannot be used to authenticate or retrieve secrets without a valid 1Password token. They serve as stable references so scripts do not need to hardcode item names (which can change).

### `configs/final.env` -- Full Environment with `op://` References (Gitignored)

**Purpose:** Complete environment file designed for use with `op run`, which resolves `op://` URIs to actual values at runtime. No plaintext secrets ever touch disk in this file.

**Usage:**
```bash
op run --env-file=configs/final.env -- terraform plan
op run --env-file=configs/final.env -- ansible-playbook site.yml
```

**Contents:**

| Variable | op:// Reference | Purpose |
|----------|----------------|---------|
| `OP_CONNECT_HOST` | `op://Homelab/1Password-Connect-Server/server/hostname` | Connect server URL |
| `OP_CONNECT_TOKEN` | `op://Homelab/1Password-Connect-Server/server/credential` | Connect JWT |
| `ANTHROPIC_API_KEY` | `op://Dev/<uuid>/credentials/api_key` | Claude API key |
| `CLAUDE_CODE_AUTH_KEY` | `op://Dev/<uuid>/credentials/oauth_token` | Claude Code auth |
| `GOOGLE_API_KEY` | `op://Dev/<uuid>/credentials/api_key` | Google AI API key |
| `PERPLEXITY_API_KEY` | `op://Dev/<uuid>/credentials/api_key` | Perplexity API key |
| `CONTEXT7_API_KEY` | `op://Dev/<uuid>/credentials/api_key` | Context7 MCP key |
| `TODOIST_API_KEY` | `op://Dev/<uuid>/credentials/api_key` | Todoist MCP key |
| `SSH_AUTH_SOCK` | `~/.1password/agent.sock` (literal) | SSH agent socket |
| `ANSIBLE_CONFIG` | Literal path | Ansible config path |
| `TF_VAR_proxmox_ve_datastore_id` | `local-lvm` (literal) | Default datastore |
| `TF_VAR_proxmox_ve_node_name` | `node-02` (literal) | Default PVE node |

**Intentional omission:** `PROXMOX_VE_*` variables are deliberately absent. The bpg/proxmox provider reads Proxmox credentials from the 1Password Connect data sources in `infrastructure/main.tf`, not from the environment.

### `.env.example` -- Setup Template (Tracked)

**Purpose:** Onboarding template. Copy to `.env.d/terraform.env` and fill in real values.

Contains the same structure as `terraform.env` with placeholder values and comments explaining each variable. Also includes the warning about never setting `PROXMOX_VE_*` env vars.

## Credential Flow Diagram

```
                    .env.d/terraform.env
                    (sourced into shell)
                           |
                    TF_VAR_op_connect_host ──────────┐
                    TF_VAR_op_connect_token ─────────┤
                           |                         |
                    ┌──────┴──────┐           ┌──────┴──────┐
                    │  terraform  │           │ 1Password   │
                    │  plan/apply │──────────>│ Connect     │
                    └──────┬──────┘           │ (VIP)       │
                           |                  └──────┬──────┘
                           |                         |
                    ┌──────┴──────────────────┐      |
                    │ infrastructure/main.tf  │<─────┘
                    │                         │  Reads at plan time:
                    │ data "onepassword_item" │  - Proxmox endpoint + password
                    │   - proxmox_tf          │  - SSH private key
                    │   - pve_root            │  - K3s cluster token
                    │   - k3s_cluster         │  - PostgreSQL password
                    │   - op_connect_server   │  - Connect credentials-b64
                    └─────────────────────────┘
```

For non-Terraform tools:

```
    configs/final.env                    .env.d/base.env
    (op:// references)                   (some plaintext)
          |                                    |
    ┌─────┴─────┐                       ┌──────┴──────┐
    │  op run    │                       │   source    │
    │  resolves  │                       │  into shell │
    │  at runtime│                       └──────┬──────┘
    └─────┬─────┘                               |
          |                              SSH_AUTH_SOCK
    Real values in                       ANSIBLE_CONFIG
    ephemeral env                        TODOIST_API_KEY
```

## Deleted Files and Why

These files were removed during the environment cleanup. Documenting them here to prevent re-introduction.

### `.env.saved` -- Plaintext Secret Dump

**Problem:** Contained plaintext `PROXMOX_VE_API_TOKEN`, `PROXMOX_VE_USERNAME`, and `PROXMOX_VE_PASSWORD`. When sourced (or even present in shell history), these environment variables silently overrode the bpg/proxmox provider block configuration in `main.tf`. This caused "API token format" errors because the provider was using the stale env var values instead of the fresh 1Password Connect values.

**Resolution:** Deleted. All Proxmox auth now flows through 1Password Connect. The provider block in `main.tf` reads credentials via `data "onepassword_item"` data sources.

### `.env.d/proxmox.env` -- Plaintext Proxmox Credentials

**Problem:** Contained plaintext Proxmox root password and API token. Redundant with the 1Password Connect flow and posed the same override risk as `.env.saved`.

**Resolution:** Deleted. Replaced by 1Password Connect data sources.

### `.env.d/1password.env` -- Conflicting Auth Modes

**Problem:** Contained both `OP_CONNECT_TOKEN` and `OP_SERVICE_ACCOUNT_TOKEN`. These are mutually exclusive 1Password auth modes. Having both set caused silent failures where the `op` CLI and Terraform provider would use conflicting auth paths.

**Resolution:** Deleted. Connect auth (`OP_CONNECT_HOST` + `OP_CONNECT_TOKEN`) is set only in `.env.d/terraform.env` and `configs/final.env`. Service account token is not used in any active env file.

### `.env.d/llm.env` -- Plaintext API Keys

**Problem:** Contained plaintext AI/LLM API keys (Anthropic, Google, Perplexity).

**Resolution:** Deleted. Moved to `configs/final.env` as `op://` references resolved at runtime by `op run`.

## Environment Gotchas

These are environment-specific gotchas that have caused real debugging sessions. They are also listed in [technical-gotchas.md](./technical-gotchas.md) for cross-reference.

### PROXMOX_VE_* env vars override provider config

The bpg/proxmox Terraform provider reads `PROXMOX_VE_API_TOKEN`, `PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD`, and `PROXMOX_VE_ENDPOINT` from the environment automatically. If any of these are set, they **silently override** whatever is configured in the `provider "proxmox" {}` block in HCL.

**Symptom:** `terraform plan` fails with "API token format" or authentication errors, even though `main.tf` has correct credentials from 1Password Connect.

**Root cause:** A stale `PROXMOX_VE_API_TOKEN` in the environment (from a previously-sourced env file, `.bashrc`, or parent shell) takes precedence over the provider block.

**Fix:** Never set `PROXMOX_VE_*` environment variables. Verify with:
```bash
env | grep PROXMOX_VE
# Should return nothing
```

### 1Password auth modes are mutually exclusive

1Password has two authentication modes:
- **Connect mode:** `OP_CONNECT_HOST` + `OP_CONNECT_TOKEN` (talks to self-hosted Connect server)
- **Service Account mode:** `OP_SERVICE_ACCOUNT_TOKEN` (talks to 1Password cloud)

Having both set causes undefined behavior. The `op` CLI, Terraform provider, and Ansible lookup plugin may each pick a different mode, leading to silent failures or "vault not found" errors.

**Fix:** Only set variables for one mode at a time. In this project, Connect mode is the standard. When using `op` CLI commands in scripts that run in a Connect environment, strip the Connect variables:
```bash
env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get ...
```

### `op` CLI hangs in non-interactive shells

The `PG_CONN_STR` in `terraform.env` uses a `$(op item get ...)` subcommand. If the `op` CLI has no active session (no biometric auth, no service account token, and Connect mode is stripped), it will attempt to prompt for authentication -- and hang indefinitely in a non-interactive shell (e.g., `source` inside a script, CI/CD, tmux without a terminal).

**Fix:**
1. Ensure `op` has an active session before sourcing: `op account list` should show a signed-in account.
2. If using `op` in automation, use a service account token or ensure biometric unlock is available.
3. The `2>/dev/null` on the `op item get` command in `terraform.env` suppresses error output but does not prevent the hang. A timeout wrapper may be needed for CI contexts.

### Proxmox privileged LXC operations require root@pam

Certain Proxmox API operations (specifically, setting privileged LXC feature flags like `nesting`, `keyctl`, `fuse`) perform a string equality check: `$authuser ne 'root@pam'`. This means API tokens -- even tokens created under `root@pam` with `privsep=0` (full privileges) -- fail this check.

**Fix:** Use username/password authentication (`root@pam` + password) for Terraform operations that manage privileged LXC containers. This is why `main.tf` uses `username = "root@pam"` + `password` from 1Password instead of an API token.

### Docker in LXC needs AppArmor bypass

When running Docker inside a Proxmox LXC container, Docker Compose services may fail with AppArmor denials. The LXC container's AppArmor profile restricts operations that Docker expects to perform.

**Fix:** Add `security_opt: [apparmor:unconfined]` to the service definition in `docker-compose.yml`:
```yaml
services:
  my-service:
    image: example:latest
    security_opt:
      - apparmor:unconfined
```

### Connect data directory permissions

The 1Password Connect containers run as `opuser` (UID 999) inside the Docker container. The data directory must be owned by this user, or Connect will fail to start with permission errors.

**Fix:**
```bash
chown 999:999 /opt/op-connect/data
```

## Typical Developer Session

### Running Terraform

```bash
# 1. Source the Terraform environment
source .env.d/terraform.env

# 2. Verify no conflicting env vars
env | grep PROXMOX_VE  # Should be empty

# 3. Run Terraform
cd infrastructure
terraform plan
terraform apply
```

### Running Ansible

```bash
# Option A: Source base env (has SSH_AUTH_SOCK + ANSIBLE_CONFIG)
source .env.d/base.env
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml

# Option B: Use op run for full environment
op run --env-file=configs/final.env -- ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml
```

### Running arbitrary commands with all secrets

```bash
# op resolves all op:// URIs, injects into ephemeral env, runs command
op run --env-file=configs/final.env -- <command>
```

## Adding New Secrets

1. **Store the secret in 1Password** (Homelab or Dev vault, depending on purpose).
2. **Add the UUID to `configs/base.env`** if scripts need to reference the item by UUID.
3. **Add an `op://` reference to `configs/final.env`** for `op run` resolution.
4. **If Terraform needs it**, add a `data "onepassword_item"` in `main.tf` and pass the value to modules via variables. Do NOT add it as a `TF_VAR_*` env var (only the Connect token gets this treatment).
5. **Never add plaintext secrets to tracked files.** Use `op://` references or read from 1Password at runtime.
