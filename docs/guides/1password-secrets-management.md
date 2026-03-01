# Guide: 1Password Secrets Management Integration

This guide covers how 1Password serves as the single source of truth for all secrets in this
homelab project. It documents your existing setup, explains each integration layer, and provides
patterns for extending secret management across Terraform, Ansible, Kubernetes, and local
development.

**Your setup at a glance:** You already have a 1Password Connect server running at
`op-connect.homelab.ts.net` (accessible over Tailscale), a service account, the `op` CLI
installed, and the Terraform `1Password/onepassword` provider configured. This guide ties all
those pieces together.

## Prerequisites

- 1Password account with a **dedicated shared vault** (Connect cannot access Personal/Private vaults)
- 1Password CLI (`op`) v2.18.0+ installed ([install script](#appendix-a-installing-the-1password-cli))
- A running 1Password Connect server (you have one at `https://op-connect.homelab.ts.net`)
- Connect access token (JWT) and/or service account token

## Key documentation

| Topic | URL |
|---|---|
| 1Password Connect overview | https://developer.1password.com/docs/connect/ |
| Connect getting started | https://developer.1password.com/docs/connect/get-started/ |
| Connect API reference | https://developer.1password.com/docs/connect/api-reference/ |
| Connect server GitHub | https://github.com/1Password/connect |
| Connect Helm charts GitHub | https://github.com/1Password/connect-helm-charts |
| Terraform provider docs | https://developer.1password.com/docs/terraform/ |
| Terraform provider registry | https://registry.terraform.io/providers/1Password/onepassword/latest/docs |
| Terraform provider GitHub | https://github.com/1Password/terraform-provider-onepassword |
| Kubernetes operator docs | https://developer.1password.com/docs/k8s/operator/ |
| Kubernetes operator GitHub | https://github.com/1Password/onepassword-operator |
| External Secrets Operator — 1Password Connect | https://external-secrets.io/latest/provider/1password-automation/ |
| External Secrets Operator — 1Password SDK | https://external-secrets.io/latest/provider/1password-sdk/ |
| CLI secret references | https://developer.1password.com/docs/cli/secret-references/ |
| CLI secret reference syntax | https://developer.1password.com/docs/cli/secret-reference-syntax/ |
| Service accounts overview | https://developer.1password.com/docs/service-accounts/ |
| Secrets automation overview | https://developer.1password.com/docs/secrets-automation/ |

---

## Implementation order

Work through these in order — each step is independent and testable before moving to the next.
Ranked by: what's required first, easiest to test, and least risk if you need to rollback.

| Priority | Part | What | Test method | Rollback |
|---|---|---|---|---|
| 1 | Part 2 | CLI (`op run`/`op inject`) | Already working — verify with `op read` | N/A |
| 2 | Part 3 | Terraform data sources | `terraform plan` (no apply needed) | Delete the data source HCL |
| 3 | Part 4 | Ansible lookup | `ansible -m debug` or `--check` | Revert `group_vars` to ansible-vault |
| 4 | Parts 5+6 | ESO in K8s | `kubectl get externalsecret` | `helm uninstall external-secrets` |
| 5 | Part 7 | Connect in K8s | Health endpoint inside cluster | **Hard** — keep Connect external instead |

> **Why this order:** Each step only touches one tool. CLI is already working. Terraform data
> sources are read-only (no infrastructure changes). Ansible lookups are standalone. K8s steps
> require a running cluster and have wider blast radius.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          1Password Cloud                                   │
│    ┌──────────────┐    ┌──────────────┐                                    │
│    │ Homelab Vault │    │   Dev Vault  │                                    │
│    │   (infra)     │    │  (API keys)  │                                    │
│    └──────┬───────┘    └──────┬───────┘                                    │
└───────────┼───────────────────┼────────────────────────────────────────────┘
            │                   │
            ▼                   ▼
  ┌─────────────────────────────────────┐
  │  1Password Connect Server           │
  │  op-connect.homelab.ts.net        │
  │  (connect-api + connect-sync)       │
  │  Local cache → unlimited reads      │
  └──────────┬──────────────────────────┘
             │ REST API + JWT auth
             │
   ┌─────────┼──────────────────────────────────────────────┐
   │         │                                              │
   ▼         ▼                    ▼                         ▼
┌────────┐ ┌────────────────┐  ┌────────────────────┐  ┌───────────┐
│ op CLI │ │ Terraform      │  │ K8s Operator / ESO │  │ Ansible   │
│        │ │ (onepassword   │  │ (in-cluster)       │  │ (connect  │
│        │ │  provider)     │  │                    │  │  lookup)  │
└────┬───┘ └───────┬────────┘  └────────┬───────────┘  └─────┬─────┘
     │             │                    │                     │
     ▼             ▼                    ▼                     ▼
 Local dev    Terraform state      K8s Secrets           Playbook
 env vars     (reads secrets)      (synced from 1P)      variables
```

---

## Part 1: Your existing setup

### 1.1 Vaults and items

You have two 1Password vaults scoped for this project:

| Vault | ID | Purpose |
|---|---|---|
| **Homelab** | `e2xu6xow3lm3xssqph2jftrny4` | Infrastructure credentials — Proxmox, SSH, Connect server |
| **Dev** | `qxhlzrgegpplamzkgg7kuxnhmm` | API keys — LLMs, MCP servers, development tools |

**Items in Homelab vault:**

| Env Var | Item ID | Fields |
|---|---|---|
| `OP_PROXMOX_TF` | `pe4n6llwr2jkwpxzo6xcvvi55y` | `credentials/endpoint`, `credentials/id`, `credentials/token`, `password` |
| `OP_PROXMOX_SSH` | `k5dlujekat5v7jw23i4p6t2xem` | `credentials/username`, `credentials/password`, `private key` |
| `OP_CONNECT` | `h4piit3akfgu7urj2hys7y6aye` | `hostname`, `credential` |
| `OP_SERVICE_ACCT` | `ouvkgfdksmyaswmnpsbpx5su44` | `credential` |

**Items in Dev vault:**

| Env Var | Item ID | Fields |
|---|---|---|
| `OP_LLM_ANTHROPIC` | `rlnittrfv6hyxeuachhhpay75e` | `credentials/api_key` |
| `OP_LLM_CLAUDE` | `ceawx2expj6ricl2z4yixowu64` | `credentials/oauth_token` |
| `OP_LLM_GOOGLE` | `ilvgw66uqqdl6yab3rfrgcm4vi` | `credentials/api_key` |
| `OP_LLM_PERPLEXITY` | `4v766mc67oz3dchdexpya3eisu` | `credentials/api_key` |
| `OP_MCP_CONTEXT7` | `uvxvcsx2xiogz6cbqlyq7b3eza` | `credentials/api_key` |
| `OP_MCP_TODOIST` | `krj2vx6b6kvdj5enmxattiavp4` | `credentials/api_key` |

### 1.2 Authentication methods available

You have **two** authentication methods configured:

| Method | Token Format | When to Use |
|---|---|---|
| **Connect Server** | JWT (`eyJhbG...`) via `OP_CONNECT_TOKEN` | Terraform, Kubernetes, any REST API consumer |
| **Service Account** | `ops_eyJ...` via `OP_SERVICE_ACCOUNT_TOKEN` | CLI (`op run`, `op inject`), CI/CD, scripts |

**Key difference:** Connect tokens authenticate against your self-hosted Connect server (local
cache, unlimited reads, low latency). Service account tokens authenticate directly against
1Password cloud (rate-limited but zero infrastructure).

**Docs:**
- [Service Accounts vs Connect](https://developer.1password.com/docs/secrets-automation/)
- [Connect security model](https://developer.1password.com/docs/connect/security/)
- [Service account security](https://developer.1password.com/docs/service-accounts/security/)

### 1.3 Connect server details

Your Connect server runs at `https://op-connect.homelab.ts.net`, accessible over your
Tailscale network. It consists of two components:

- **`connect-api`** — REST API server (port 8080 by default)
- **`connect-sync`** — Keeps local encrypted cache synchronized with 1Password cloud

**Health check:**

```bash
source .env.saved  # or: source .env.d/1password.env

# Heartbeat (no auth required)
curl -sk https://op-connect.homelab.ts.net/heartbeat

# Health check (no auth required)
curl -sk https://op-connect.homelab.ts.net/health

# List vaults (requires auth)
curl -sk -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
  https://op-connect.homelab.ts.net/v1/vaults | python3 -m json.tool
```

> **Uncertainty:** I don't know whether your Connect server is running as a Docker container,
> a systemd service, or on Kubernetes. The architecture is the same regardless — two containers
> (`1password/connect-api` and `1password/connect-sync`) sharing a `1password-credentials.json`
> file. If it's not yet deployed in K8s, see [Part 5: Kubernetes integration](#part-5-kubernetes-integration)
> for deploying it via Helm + Flux.

**Docs:**
- [Connect API endpoints](https://developer.1password.com/docs/connect/api-reference/)
- [Connect server GitHub](https://github.com/1Password/connect)

### 1.4 Environment files

Your credentials flow through a layered env file system:

```
.env.d/1password.env      Non-secret identifiers (vault IDs, item IDs, Connect URL)
       │                   Also contains Connect token + SA token (these ARE secrets)
       ▼
.env.d/terraform.env      TF_VAR_* variables with resolved values
       │
       ▼
scripts/env-load.sh       Combines base.env + op:// references → final.env → .env
       │                   Uses op run + op inject to resolve secrets
       ▼
.env / .env.saved          Fully resolved credentials for shell sourcing
```

**Security note:** `.env.d/1password.env` and `.env.d/terraform.env` contain **actual secrets**
(JWT tokens, API tokens). These files are gitignored and must never be committed. The `.env.example`
file shows the structure without real values.

---

## Part 2: CLI integration (`op`)

The 1Password CLI is the foundation for local development and script automation.

### 2.1 Secret reference syntax

The `op://` URI is how you reference secrets without embedding them:

```
op://<vault>/<item>/<field>
op://<vault>/<item>/<section>/<field>
```

**Your actual references:**

```bash
# Proxmox API credentials
op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/endpoint
op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/id
op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_TF}/credentials/token

# SSH key (with query parameter for format)
op://${OP_VAULT_HOMELAB}/${OP_PROXMOX_SSH}/private key?ssh-format=openssh

# LLM API keys
op://${OP_VAULT_DEV}/${OP_LLM_ANTHROPIC}/credentials/api_key
```

References are **case-insensitive**. Vault/item can be a name or UUID. If a name contains
spaces, it must be quoted. Query parameters control output format (e.g., `?ssh-format=openssh`).

**Docs:** https://developer.1password.com/docs/cli/secret-reference-syntax/

### 2.2 `op run` — inject secrets into commands

`op run` scans environment variables for `op://` references, resolves them, and runs a subprocess
with the real values. Secrets are **automatically masked** in stdout/stderr.

```bash
# Run terraform with secrets injected from an env file
op run --env-file .env -- terraform plan

# Or export references first, then run
export PROXMOX_VE_API_TOKEN="op://Homelab/Proxmox-TF/credentials/token"
op run -- curl -H "Authorization: Bearer $PROXMOX_VE_API_TOKEN" https://...
```

With an env file containing `op://` references:

```bash
# .env file with op:// references
DB_PASSWORD=op://Homelab/PostgreSQL/password
API_KEY=op://Dev/MyApp/api-key

op run --env-file=.env -- docker compose up
```

**Gotcha:** `op run` only scans environment variables — it does NOT find `op://` references in
command-line arguments. This means `op run -- echo "op://Homelab/item/field"` will NOT resolve
the reference. Use `op read` for one-off reads or `op inject` for template files.

**Your `init-env` function** (in `scripts/env-load.sh`) uses this pattern:

```bash
init-env() {
    cp -v .env .env.bak
    op run --env-file .env --no-masking -- cat .env | op inject > .env.load
    source .env.load && rm .env.load
}
```

This resolves all `op://` references in `.env` and produces a `.env.load` with real values.

**Docs:**
- [op run reference](https://developer.1password.com/docs/cli/reference/commands/run/)
- [Secrets in environment variables](https://developer.1password.com/docs/cli/secrets-environment-variables/)

### 2.3 `op inject` — template file replacement

`op inject` resolves `{{ op://... }}` placeholders in template files. Note the double-brace
syntax (different from bare `op://` in env vars).

```bash
# Template file (config.tpl)
database:
  host: localhost
  password: {{ op://Homelab/PostgreSQL/password }}

# Inject secrets
op inject --in-file config.tpl --out-file config.yaml

# Or via stdin/stdout
cat config.tpl | op inject > config.yaml
```

**Your MCP config pattern** uses `op inject` to convert `.op.json` template files to resolved
`.json` files:

```bash
# scripts/config-mcps.sh
op inject -i ".mcp.op.json" -o ".mcp.json"
```

The `.mcp.op.json` contains `op://` references for API keys:

```json
{
  "mcpServers": {
    "taskmaster-ai": {
      "env": {
        "ANTHROPIC_API_KEY": "op://${OP_VAULT_DEV}/${OP_LLM_ANTHROPIC}/credentials/api_key"
      }
    }
  }
}
```

> **Note:** The `${OP_VAULT_DEV}` shell variable expansion happens at the shell level (via
> `op run --env-file` or `source .env.d/1password.env`), then `op inject` resolves the
> resulting `op://` URIs. This is a two-stage resolution.

**Docs:** https://developer.1password.com/docs/cli/reference/commands/inject/

### 2.4 `op read` — read a single secret

For one-off reads in scripts or debugging:

```bash
# Read a secret to stdout
op read "op://Homelab/Proxmox-TF/credentials/token"

# Write to a file (e.g., SSH key)
op read "op://Homelab/Proxmox-SSH/private key?ssh-format=openssh" --out-file ~/.ssh/proxmox_ed25519
chmod 600 ~/.ssh/proxmox_ed25519
```

**Docs:** https://developer.1password.com/docs/cli/reference/commands/read/

---

## Part 3: Terraform integration

Your `infrastructure/main.tf` already configures the 1Password Terraform provider:

```hcl
# infrastructure/main.tf (existing)
provider "onepassword" {
  connect_token = var.op_connect_token    # env: TF_VAR_op_connect_token
  connect_url   = var.op_connect_host     # env: TF_VAR_op_connect_host
}
```

### 3.1 Provider authentication methods

The provider supports three authentication methods:

| Method | Config | Environment Variable |
|---|---|---|
| **Connect Server** (your current setup) | `connect_token` + `connect_url` | `OP_CONNECT_TOKEN` + `OP_CONNECT_HOST` |
| **Service Account** | `service_account_token` | `OP_SERVICE_ACCOUNT_TOKEN` |
| **Desktop App** (local dev only) | `account = "Personal"` | `OP_ACCOUNT` |

**Your current setup** uses Connect Server via `TF_VAR_*` environment variables set in
`.env.d/terraform.env`:

```bash
# .env.d/terraform.env (existing)
export TF_VAR_op_connect_host=https://op-connect.homelab.ts.net
export TF_VAR_op_connect_token=eyJhbG...
```

**Docs:** https://registry.terraform.io/providers/1Password/onepassword/latest/docs

### 3.2 Reading secrets with data sources

Use `onepassword_item` data sources to read credentials from 1Password instead of passing them
as `TF_VAR_*` environment variables:

```hcl
# Look up the vault by name
data "onepassword_vault" "homelab" {
  name = "Homelab"
}

# Read Proxmox credentials from 1Password
data "onepassword_item" "proxmox_tf" {
  vault = data.onepassword_vault.homelab.uuid
  title = "Proxmox Terraform"     # The item title in 1Password
}

# Use the values
provider "proxmox" {
  endpoint  = data.onepassword_item.proxmox_tf.url
  api_token = "${data.onepassword_item.proxmox_tf.username}=${data.onepassword_item.proxmox_tf.password}"
  insecure  = true
}
```

**Available fields on `onepassword_item`:**

| Field | Description |
|---|---|
| `username` | Login username |
| `password` | Login password |
| `url` | Primary URL field |
| `section` | Nested blocks for custom sections |

> **Uncertainty:** The exact field mapping depends on how the item is structured in 1Password.
> The `username`, `password`, and `url` fields map to the standard Login item fields. For custom
> fields (like `credentials/endpoint`), you may need to use `section` blocks. Check the
> [provider docs](https://registry.terraform.io/providers/1Password/onepassword/latest/docs/data-sources/item)
> for the exact syntax for reading custom sections and fields.

### 3.3 Eliminating TF_VAR environment variables

The current approach passes Proxmox credentials through environment variables:

```
.env → TF_VAR_proxmox_ve_token → variable "proxmox_ve_token" → provider "proxmox"
```

With the 1Password provider, you can eliminate this chain entirely — Terraform reads secrets
directly from 1Password at plan/apply time. Only the Connect token and URL need to be in the
environment:

```
.env → TF_VAR_op_connect_token + TF_VAR_op_connect_host → provider "onepassword" → data sources → provider "proxmox"
```

This means fewer environment variables to manage, no secrets in `.env.saved`, and credentials
rotate in 1Password without touching Terraform variables.

### 3.4 Creating items with resources

The provider can also create and manage 1Password items:

```hcl
# Generate and store a K3s token in 1Password
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "onepassword_item" "k3s_token" {
  vault    = data.onepassword_vault.homelab.uuid
  category = "password"
  title    = "K3s Cluster Token"
  password = random_password.k3s_token.result
  tags     = ["k3s", "terraform-managed"]
}
```

**Caution:** `terraform destroy` will delete `onepassword_item` resources from 1Password. Use
`lifecycle { prevent_destroy = true }` if you want to protect items from accidental deletion.

**Docs:**
- [Data source: onepassword_item](https://registry.terraform.io/providers/1Password/onepassword/latest/docs/data-sources/item)
- [Resource: onepassword_item](https://registry.terraform.io/providers/1Password/onepassword/latest/docs/resources/item)
- [Provider GitHub](https://github.com/1Password/terraform-provider-onepassword)

---

## Part 4: Ansible integration

There are **three** ways to read 1Password secrets in Ansible. The right choice depends on
whether you need inline lookups (in `group_vars`) or task-based retrieval.

### 4.1 Option A: `community.general.onepassword` lookup (recommended)

This is a **lookup plugin** — meaning it works inline in variable definitions, `group_vars`,
templates, and anywhere Jinja2 is evaluated. Connect mode was added in **community.general
v8.1.0** (no `op` CLI required).

```bash
ansible-galaxy collection install community.general
```

**Docs:** https://docs.ansible.com/ansible/latest/collections/community/general/onepassword_lookup.html

#### Configure the connection

Set environment variables (or pass as lookup parameters):

```bash
export OP_CONNECT_HOST="https://op-connect.homelab.ts.net"
export OP_CONNECT_TOKEN="<your-connect-token>"
```

#### Use in group_vars (inline lookups)

```yaml
# ansible/group_vars/k3s_cluster.yml — 1Password alternative to ansible-vault
---
k3s_token: "{{ lookup('community.general.onepassword', 'K3s Cluster Token',
              field='password', vault='Homelab') }}"

k3s_datastore_endpoint: >-
  postgres://k3s:{{ lookup('community.general.onepassword', 'PostgreSQL K3s',
              field='password', vault='Homelab') }}@10.0.0.45:5432/k3s
```

**Lookup parameters:**

| Parameter | Default | Description |
|---|---|---|
| `_terms` (positional) | — | Item name or UUID (required) |
| `field` | `"password"` | Field label to return |
| `section` | — | Section containing the field |
| `vault` | — | Vault name or UUID (searches all if omitted) |
| `connect_host` | `$OP_CONNECT_HOST` | Connect server URL |
| `connect_token` | `$OP_CONNECT_TOKEN` | Connect JWT token |
| `service_account_token` | `$OP_SERVICE_ACCOUNT_TOKEN` | SA token (alt to Connect) |

This replaces `ansible-vault` encrypted files — secrets are fetched at runtime from 1Password
instead of being stored encrypted in Git.

**Related plugins:** `community.general.onepassword_raw` returns the entire item as a dict
(all fields). `community.general.onepassword_doc` retrieves stored documents (files).

### 4.2 Option B: `onepassword.connect` collection (task-based modules)

The official 1Password collection provides **modules** (not lookup plugins). This means they
run as tasks and require `register:` to capture values — you cannot use them inline in
`group_vars` variable definitions.

```bash
ansible-galaxy collection install onepassword.connect
```

**Docs:** https://github.com/1Password/ansible-onepasswordconnect-collection

**Modules available:**
- `onepassword.connect.field_info` — Read a single field value
- `onepassword.connect.item_info` — Read full item data
- `onepassword.connect.generic_item` — Create/update/delete items

```yaml
- name: Get K3s token from 1Password
  onepassword.connect.field_info:
    item: K3s Cluster Token
    field: password
    vault: Homelab
  register: k3s_token_result
  no_log: true

- name: Use the token
  ansible.builtin.debug:
    msg: "Token is {{ k3s_token_result.field.value }}"
```

**When to use this over the lookup:** When you need to **create or update** items in 1Password
from Ansible (the `generic_item` module). The `community.general` lookup is read-only.

### 4.3 Option C: `op` CLI via pipe lookup

For one-off reads without installing collections:

```yaml
# Using op read via Ansible's pipe lookup
k3s_token: "{{ lookup('pipe', 'op read op://Homelab/K3s-Cluster-Token/password') }}"
```

Requires the `op` CLI installed on the Ansible controller and either `OP_SERVICE_ACCOUNT_TOKEN`
or an authenticated desktop app session.

### 4.4 Tradeoffs: ansible-vault vs 1Password

| Feature | ansible-vault | 1Password (lookup) |
|---------|--------------|-------------------|
| Secrets stored in | Git (encrypted) | 1Password cloud (cached locally) |
| Rotation | Edit file, re-encrypt, commit | Update in 1Password, instant |
| Offline access | Yes (encrypted file is in repo) | Requires Connect server |
| Sharing | Share vault password | Share 1Password vault |
| Audit trail | Git log | 1Password activity log |
| Complexity | Low (one password) | Medium (requires Connect server or SA token) |
| Use in group_vars | Yes | Yes (lookup plugin only, not modules) |

**Recommendation:** Use `community.general.onepassword` lookup with Connect mode for runtime
secrets (passwords, tokens, API keys). Keep `ansible-vault` as a fallback for environments
where the Connect server is unreachable.

---

## Part 5: Kubernetes integration

This is where the most decisions need to be made. There are **three** approaches for getting
1Password secrets into Kubernetes, and you should pick **one** (not multiple).

### 5.1 Option A: External Secrets Operator (Recommended)

The External Secrets Operator (ESO) is provider-agnostic, widely adopted, and has first-class
FluxCD documentation. It supports both 1Password Connect and 1Password SDK (service account)
backends. Current version is **v2.0.0** (chart version 2.0.0, released February 2025).

> **Note:** The ESO docs now recommend the **SDK provider** over the Connect provider:
> *"Consider using 1Password SDK provider instead. It uses an official SDK created by 1Password.
> It's feature complete and has parity with this provider's capabilities."* Both are fully
> supported; the SDK provider simply doesn't require a Connect server deployment.

**GitHub:** https://github.com/external-secrets/external-secrets

#### Connect provider (uses your existing Connect server)

```yaml
# SecretStore pointing to your Connect server
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: onepassword-connect
  namespace: default
spec:
  provider:
    onepassword:
      connectHost: https://op-connect.homelab.ts.net
      vaults:
        Homelab: 1       # vault name: priority order
        Dev: 2
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-token
            key: token
```

The token secret (must be created manually or via SOPS — see [bootstrap problem](#55-the-bootstrap-problem)):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-token
type: Opaque
stringData:
  token: <your-connect-access-token>
```

**ExternalSecret example:**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: default
spec:
  secretStoreRef:
    kind: SecretStore
    name: onepassword-connect
  target:
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: PostgreSQL K3s        # 1Password item title
        property: password         # field label
    - secretKey: DB_USERNAME
      remoteRef:
        key: PostgreSQL K3s
        property: username
```

**Requirements:** Connect server v1.5.6+ for ESO compatibility.

**Docs:** https://external-secrets.io/latest/provider/1password-automation/

#### SDK provider (no Connect server required, uses service account directly)

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-sdk
spec:
  provider:
    onepasswordSDK:
      vault: Homelab               # one store per vault
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          key: token
          namespace: external-secrets
```

**ExternalSecret with SDK provider** uses a different reference format (`<item>/<field>`):

```yaml
spec:
  data:
    - secretKey: username
      remoteRef:
        key: PostgreSQL K3s/username        # format: <item>/<field>
    - secretKey: password
      remoteRef:
        key: PostgreSQL K3s/password
    - secretKey: api-key
      remoteRef:
        key: My-App/API Section/key         # format: <item>/<section>/<field>
```

**Limitation:** One `ClusterSecretStore` per vault. You'd need two stores (one for Homelab, one
for Dev).

**Docs:** https://external-secrets.io/latest/provider/1password-sdk/

### 5.2 Option B: 1Password Kubernetes Operator

The official 1Password operator uses a custom `OnePasswordItem` CRD to sync items into native
Kubernetes Secrets.

**GitHub:** https://github.com/1Password/onepassword-operator

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: db-credentials
spec:
  itemPath: "vaults/Homelab/items/PostgreSQL K3s"
```

This creates a Kubernetes Secret named `db-credentials` with key-value pairs matching the
1Password item's fields.

**Deployment via Helm:**

```bash
helm repo add 1password https://1password.github.io/connect-helm-charts

helm install connect 1password/connect \
  --set-file connect.credentials=1password-credentials.json \
  --set operator.create=true \
  --set operator.token.value=<your-connect-token>
```

**Key differences from ESO:**

| Feature | ESO | 1Password Operator |
|---------|-----|--------------------|
| Provider support | 50+ providers | 1Password only |
| CRD | `ExternalSecret` | `OnePasswordItem` |
| Field mapping | Explicit (pick fields) | All fields copied |
| Community | Large, active | Smaller |
| FluxCD docs | First-class | Manual Helm setup |
| Auto-restart pods | Not built-in | Yes (via annotation) |

**Auto-restart** is a unique feature — annotate a Deployment with
`operator.1password.io/auto-restart: "true"` and the operator will trigger a rolling restart
when the source 1Password item changes.

**Docs:**
- [Operator usage guide](https://github.com/1Password/onepassword-operator/blob/main/USAGEGUIDE.md)
- [Helm chart config](https://developer.1password.com/docs/k8s/helm-config/)

### 5.3 Option C: SOPS + age (current approach in FluxCD guide)

Your [FluxCD Bootstrap guide](./fluxcd-bootstrap.md) already covers SOPS + age. This approach
encrypts secrets in Git and Flux decrypts them at reconciliation time. It has **no dependency on
1Password at runtime** — secrets are baked into Git.

This is the simplest approach but has tradeoffs:

| Aspect | SOPS + age | 1Password (ESO/Operator) |
|--------|-----------|--------------------------|
| Secret rotation | Edit, re-encrypt, commit, push | Update in 1Password UI |
| Source of truth | Git | 1Password |
| Offline | Works | Requires Connect server |
| Audit | Git log | 1Password activity log |
| Key management | Age private key on cluster | Connect token on cluster |

### 5.4 Recommendation: ESO + SOPS hybrid

Use **both**, for different purposes:

1. **SOPS + age** — For the bootstrap secret only (the Connect token or SA token that ESO needs
   to authenticate with 1Password). This is the one secret that can't come from 1Password
   (chicken-and-egg).

2. **ESO with 1Password Connect** — For all application and infrastructure secrets. Secrets are
   managed in 1Password, synced into Kubernetes by ESO, and never stored in Git.

This gives you the best of both worlds: 1Password as the single source of truth, SOPS to
bootstrap the initial trust, and no secrets in Git beyond the bootstrap token.

### 5.5 The bootstrap problem

ESO needs a 1Password token to fetch secrets. But how does that token get into the cluster?
This is the **bootstrap problem** — you need a secret to fetch secrets.

**Solutions (pick one):**

1. **SOPS + age** (recommended) — Encrypt the Connect token with SOPS, commit to Git, Flux
   decrypts it on the cluster. You already have this set up from the [FluxCD guide](./fluxcd-bootstrap.md).

   ```bash
   # Create the token secret manifest
   kubectl create secret generic onepassword-connect-token \
     --from-literal=token="${OP_CONNECT_TOKEN}" \
     --namespace=external-secrets \
     --dry-run=client -o yaml > onepassword-token.sops.yaml

   # Encrypt with SOPS
   sops --encrypt --in-place onepassword-token.sops.yaml
   ```

2. **Manual `kubectl create secret`** — Apply once, never commit to Git:

   ```bash
   kubectl create secret generic onepassword-connect-token \
     --from-literal=token="${OP_CONNECT_TOKEN}" \
     --namespace=external-secrets
   ```

   Downside: if the cluster is rebuilt, you must re-apply manually.

3. **Sealed Secrets** — Another Kubernetes-native encryption approach, but adds another tool.

---

## Part 6: FluxCD + ESO deployment

This section covers deploying ESO via FluxCD with 1Password as the backend. The critical
challenge is a **CRD race condition** — ESO CRDs must be installed before any `SecretStore`
or `ExternalSecret` resources.

### 6.1 Add the ESO Helm source

**`infrastructure/kubernetes/infrastructure/sources/external-secrets.yaml`:**

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: external-secrets
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.external-secrets.io
```

### 6.2 Deploy ESO with CRDs

**`infrastructure/kubernetes/infrastructure/controllers/external-secrets/namespace.yaml`:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
```

**`infrastructure/kubernetes/infrastructure/controllers/external-secrets/release.yaml`:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-secrets
  namespace: external-secrets
spec:
  interval: 30m
  chart:
    spec:
      chart: external-secrets
      version: "2.x"          # Pin to a specific version (current: 2.0.0)
      sourceRef:
        kind: HelmRepository
        name: external-secrets
        namespace: flux-system
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    installCRDs: true          # Master toggle — installs all ESO CRDs
```

> **Note on CRDs:** The Helm value is `installCRDs` (camelCase, default: `true`), not
> `crds.create`. CRDs are installed using server-side apply due to their size. For Flux
> HelmReleases, this works automatically. Individual CRDs can be toggled via
> `crds.createClusterSecretStore`, `crds.createSecretStore`, etc.

**`infrastructure/kubernetes/infrastructure/controllers/external-secrets/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - release.yaml
```

### 6.3 Deploy the SecretStore (depends on ESO)

The `SecretStore` and `ExternalSecret` resources must deploy **after** ESO CRDs are registered.
Use Flux's `dependsOn`:

**`infrastructure/kubernetes/infrastructure/configs/onepassword-secretstore.yaml`:**

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepassword:
      connectHost: https://op-connect.homelab.ts.net
      vaults:
        Homelab: 1
        Dev: 2
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-token
            key: token
            namespace: external-secrets
```

The `infra-configs` Kustomization already has `dependsOn: infra-controllers` (from the
[FluxCD guide](./fluxcd-bootstrap.md#step-4-set-up-repository-structure)), so the ordering is
handled.

### 6.4 Use ExternalSecrets in applications

Once the `ClusterSecretStore` is available, any namespace can create `ExternalSecret` resources:

```yaml
# apps/my-app/external-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: My App Database       # 1Password item title
        property: url
    - secretKey: API_KEY
      remoteRef:
        key: My App API Key
        property: credential
```

**Docs:** https://external-secrets.io/latest/examples/gitops-using-fluxcd/

---

## Part 7: Deploying Connect server in Kubernetes (future)

If you want to migrate your Connect server into the K3s cluster (instead of running it
externally), deploy it via Flux:

### 7.1 Add the 1Password Helm source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: 1password
  namespace: flux-system
spec:
  interval: 1h
  url: https://1password.github.io/connect-helm-charts
```

### 7.2 Deploy Connect via HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: onepassword-connect
  namespace: onepassword
spec:
  interval: 30m
  chart:
    spec:
      chart: connect
      sourceRef:
        kind: HelmRepository
        name: 1password
        namespace: flux-system
  install:
    createNamespace: true
  values:
    connect:
      credentials_base64: <base64-encoded-1password-credentials.json>
```

> **Uncertainty:** The `credentials_base64` value should be your `1password-credentials.json` file
> base64-encoded. I haven't verified the exact Helm value name — check the
> [chart values](https://github.com/1Password/connect-helm-charts/blob/main/charts/connect/values.yaml).
> The credentials file is generated when you set up Secrets Automation in the 1Password web UI.

**Gotcha:** This creates a chicken-and-egg problem — Connect runs in K8s, but ESO needs Connect
to get secrets, and Connect needs its own credentials to start. Solutions:

1. Keep Connect **outside** K8s (current approach — simplest)
2. Bootstrap Connect credentials via SOPS + age
3. Use the ESO SDK provider (service account) so Connect isn't needed at all

**Docs:**
- [Helm chart GitHub](https://github.com/1Password/connect-helm-charts)
- [Helm config reference](https://developer.1password.com/docs/k8s/helm-config/)

---

## Part 8: Possible issues and gotchas

### 8.1 Connect server availability

If the Connect server goes down, any service depending on it will fail to fetch new secrets.
Existing Kubernetes Secrets remain cached and continue to work, but rotations and new
ExternalSecrets will fail until Connect is restored.

**Mitigation:** Run Connect on infrastructure that's independent of K3s (e.g., Docker on your
NAS or a dedicated VM). This avoids circular dependencies where the cluster depends on a service
running inside itself.

### 8.2 Connect cannot access Personal/Private vaults

The Connect server can only access **dedicated shared vaults**. Personal, Private, Employee,
and default Shared vaults are off-limits. All items you want to access programmatically must
live in a vault explicitly granted to the Connect server.

**Docs:** https://developer.1password.com/docs/connect/get-started/#step-1-set-up-a-secrets-automation-workflow

### 8.3 Rate limiting (service account vs Connect)

| Method | Rate Limits |
|--------|-------------|
| Service Account | Hourly and daily limits (varies by plan) |
| Connect Server | **Unlimited** — reads from local cache |

If you use the ESO SDK provider (service account), a cluster with many ExternalSecrets polling
frequently could hit rate limits. The Connect provider avoids this entirely.

### 8.4 Token rotation

- **Connect tokens** don't expire by default but can be revoked in the 1Password web UI
- **Service account tokens** can have expiration dates (e.g., `--expires-in 90d`)

If a token is revoked/expired, all dependent services lose access. Plan for rotation:

1. Create a new token
2. Update the Kubernetes secret (via SOPS commit or `kubectl`)
3. Restart the dependent pods

### 8.5 Secret reference gotchas

- `op run` only resolves env vars, not command arguments
- `op inject` uses `{{ op://... }}` (double braces), not bare `op://`
- Vault/item names with special characters need UUIDs instead
- `op://` references are resolved at **invocation time** — they're not lazy

### 8.6 Terraform state contains secret values

When you use `data "onepassword_item"`, the resolved secret values are stored in Terraform
state. If you're using local state (`terraform.tfstate`), this file contains **plaintext
secrets**. Use a remote backend with encryption (S3 with server-side encryption, Terraform
Cloud, or the PostgreSQL backend with TLS).

### 8.7 `env-load.sh` known issues

Your `scripts/env-load.sh` has several known issues (documented in the
[future guides roadmap](./future-guides-roadmap.md#scriptsenv-loadsh--environment-loading)):

1. `op run --env-file` + heredoc `cat << EOF` don't chain correctly (line 13-14)
2. No error handling (`set -euo pipefail` missing)
3. Relative path assumptions (assumes run from repo root)
4. Both an alias and function named `init-env` (lines 67-72) — function shadows alias
5. `.env.load` left on disk if `op inject` fails

---

## Quick reference: common operations

### Read a secret from the CLI

```bash
op read "op://Homelab/Proxmox-TF/credentials/token"
```

### Run terraform with 1Password

```bash
# Minimal — only Connect credentials needed
export TF_VAR_op_connect_host="https://op-connect.homelab.ts.net"
export TF_VAR_op_connect_token="$(op read 'op://Homelab/Connect/credential')"
terraform plan
```

### Test the Connect API

```bash
source .env.d/1password.env

# Health check
curl -sk https://op-connect.homelab.ts.net/health

# List vaults
curl -sk -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
  https://op-connect.homelab.ts.net/v1/vaults

# List items in Homelab vault
curl -sk -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
  "https://op-connect.homelab.ts.net/v1/vaults/${OP_VAULT_HOMELAB}/items"

# Get a specific item
curl -sk -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
  "https://op-connect.homelab.ts.net/v1/vaults/${OP_VAULT_HOMELAB}/items/${OP_PROXMOX_TF}"
```

### Run Ansible with 1Password

```bash
# Using Connect plugin
export OP_CONNECT_HOST="https://op-connect.homelab.ts.net"
export OP_CONNECT_TOKEN="$(op read 'op://Homelab/Connect/credential')"
ansible-playbook -i inventory/k3s-cluster.yml playbooks/k3s-cluster.yml

# Using op CLI (service account)
export OP_SERVICE_ACCOUNT_TOKEN="$(op read 'op://Homelab/Service-Account/credential')"
ansible-playbook -i inventory/k3s-cluster.yml playbooks/k3s-cluster.yml
```

---

## Appendix A: Installing the 1Password CLI

Your `scripts/1password/install-client.sh` installs the CLI from the official Debian repository:

```bash
# Run the existing install script
bash scripts/1password/install-client.sh

# Verify
op --version
# Requires v2.18.0+ for service account support
```

For manual installation or other platforms, see: https://developer.1password.com/docs/cli/get-started/

## Appendix B: Connect server setup

Your `scripts/1password/install-server.sh` downloads the Connect server binary. For a
Docker-based deployment:

```yaml
# docker-compose.yml
version: '3'
services:
  connect-api:
    image: 1password/connect-api:latest
    ports:
      - "8080:8080"
    volumes:
      - ./1password-credentials.json:/home/opuser/.op/1password-credentials.json
      - onepassword-data:/home/opuser/.op/data
    environment:
      - OP_LOG_LEVEL=info

  connect-sync:
    image: 1password/connect-sync:latest
    volumes:
      - ./1password-credentials.json:/home/opuser/.op/1password-credentials.json
      - onepassword-data:/home/opuser/.op/data

volumes:
  onepassword-data:
```

Both containers share the `1password-credentials.json` file (generated during Secrets Automation
setup in the 1Password web UI) and a data volume for the encrypted cache.

**Docs:** https://developer.1password.com/docs/connect/get-started/

---

## What's next

After reviewing this guide and deciding on your Kubernetes secret management approach:

1. **Test the Connect API** — Verify your Connect server is healthy and accessible
2. **Add 1Password data sources to Terraform** — Replace `TF_VAR_*` environment variables
   with `onepassword_item` data sources for Proxmox credentials
3. **Deploy ESO via Flux** — Follow [Part 6](#part-6-fluxcd--eso-deployment) to deploy the
   External Secrets Operator
4. **Migrate application secrets** — Create `ExternalSecret` resources for each application
   instead of committing SOPS-encrypted secrets
5. **Set up the Ansible Connect lookup** — Replace `ansible-vault` files with 1Password lookups
   for runtime secrets
