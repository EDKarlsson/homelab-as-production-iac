# Claude Code Instructions

## Project Overview

Homelab IaC monorepo managing a Proxmox cluster (5 nodes) → K3s Kubernetes (3 servers + 5 agents) → 20+ applications via GitOps. Full stack: Terraform provisions VMs, Ansible configures K3s, FluxCD reconciles Kubernetes manifests.

## Repository Structure

```
infrastructure/          # Terraform root module + modules (k3s, pg-ha, op-connect, pve)
ansible/                 # Inventory, playbooks, templates for K3s + PostgreSQL
kubernetes/
  platform/controllers/  # HelmReleases: MetalLB, ingress-nginx, ESO, cert-manager, etc.
  platform/configs/      # ClusterSecretStore, issuers, ingress configs
  platform/monitoring/   # kube-prometheus-stack, Loki, Promtail, dashboards
  apps/                  # Application manifests (each has kustomization.yaml)
clusters/homelab/         # Flux Kustomization entrypoints (platform.yaml, apps.yaml, monitoring.yaml)
scripts/                 # Operational scripts: k8s/, ci/, 1password/, terraform/, docs-sync/
docs/                    # Guides, architecture, reference docs (synced to Wiki.js)
ci/allowlists/           # Policy check exception lists for CI
```

## Essential Commands

```bash
# Environment setup (required before Terraform)
source .env.d/terraform.env

# Terraform
terraform -chdir=infrastructure init
terraform -chdir=infrastructure plan
terraform -chdir=infrastructure apply

# Ansible (--forks=1 required with 1Password SSH agent)
ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-cluster.yml --forks=1

# Kubernetes validation (run before PR)
bash scripts/k8s/validate.sh          # kustomize build + kubeconform schema checks
bash scripts/ci/policy-check.sh       # Security policy enforcement

# Pre-commit hooks
pre-commit run --all-files             # terraform fmt, validate, tflint

# Cluster access
export KUBECONFIG=~/.kube/config-homelab                            # LAN only
kubectl --context=tailscale-operator.homelab.ts.net ...          # Remote via Tailscale

# Cluster health
bash scripts/k8s/k3s-verify.sh --quick
```

## Flux GitOps Dependency Chain

```
platform-controllers → platform-configs → apps
monitoring-controllers → monitoring-configs (also depends on platform-configs)
```

Adding a new CRD/controller? It goes in `platform/controllers/`. Anything that consumes those CRDs goes in `platform/configs/` or downstream. Breaking this ordering causes reconciliation failures.

## App Deployment Pattern

Every app in `kubernetes/apps/<name>/` follows this structure:
- `kustomization.yaml` — lists all resources
- `namespace.yaml` — dedicated namespace
- `deployment.yaml` or HelmRelease — the workload
- `service.yaml` + `ingress.yaml` — LAN access via ingress-nginx (nip.io)
- `tailscale-ingress.yaml` — remote access via Tailscale operator
- `external-secret.yaml` — secrets from 1Password Connect via ESO

Dual ingress is standard: nginx for LAN (`<app>.10.0.0.201.nip.io`), Tailscale for remote (`<app>.homelab.ts.net`).

## Secrets Management

**Never commit secrets.** All secrets flow through:
1. 1Password vault → 1Password Connect (HA VIP 10.0.0.72)
2. ESO ClusterSecretStore `onepassword-connect` → ExternalSecret resources → K8s Secrets
3. Terraform reads credentials via `onepassword_item` data sources

1Password custom text fields only — default Login fields (username/password) are NOT addressable by ESO `property`.

## Coding Conventions

- **Terraform**: `terraform fmt` enforced by pre-commit. Resource names use underscores (`k3s_server_1`), VM names use hyphens (`k3s-server-1`). Pin provider versions.
- **Kubernetes YAML**: Explicit, composable manifests. Pin image tags — `:latest` fails CI (use `ci/allowlists/image-tag-latest.txt` for exceptions).
- **Ansible**: `remote_user=dank`, Python interpreter `auto_silent`. SSH via 1Password agent with `IdentitiesOnly=yes`.
- **Shell scripts**: Must pass ShellCheck. Use `set -euo pipefail`.

## Git Workflow

- **Branching**: Feature branches → PR to `main`. Branch names: `feat/`, `fix/`, `docs/`, `chore/`
- **Commits**: Conventional Commits format (`feat:`, `fix:`, `docs:`, `chore:`) with scope
- **Tags**: Semver `v0.<PR#>.0` (pre-1.0 convention, PR number = minor version)
- **End of session**: Use `/finalize` command (knowledge capture → changelog → commit → PR → merge → tag)
- **Pre-commit hooks**: `terraform_fmt`, `terraform_validate`, `terraform_tflint` — these run automatically on commit

## CI/CD Pipeline

GitHub Actions (`ci-testing.yml`) runs on PR/push to main:
1. **Path filtering** — only relevant jobs run based on changed files
2. **Terraform** — fmt check, init/validate across all dirs, tflint
3. **Ansible** — syntax-check + ansible-lint
4. **Kubernetes** — kustomize build + kubeconform + policy-check.sh
5. **ShellCheck** — on changed `.sh` files
6. **Homelab smoke tests** — optional, on self-hosted runner

Policy checks (`scripts/ci/policy-check.sh`) enforce: no `:latest` tags, no wildcard chart versions, no insecure TLS skip, no relaxed SSH host key checking, no insecure Terraform providers.

## Key Technical Context

- **Proxmox provider**: `bpg/proxmox` v0.95.0. SSH username must be `root`, not PVE API user. `PROXMOX_VE_*` env vars silently override provider block — never set them.
- **1Password auth modes**: Connect vs Service Account are mutually exclusive. This repo uses Connect mode.
- **PostgreSQL**: HA cluster with keepalived VIP at 10.0.0.44. All services use the VIP.
- **K3s**: External PostgreSQL datastore (not etcd). All servers share `--datastore-endpoint` + `--token`. Agents use `--server` to join.
- **Tailscale**: All access is via Tailscale — no public internet exposure. Dual ingress on every app.
- **Python**: Use `uv` for package management, NOT `pip` directly. Python 3.13.

## User Preferences

- Prefers to **write code themselves** — provide walkthrough guides with explanations, not implementations
- Use guided walkthrough skills when applicable (`~/.claude/skills/guided-walkthrough/`, `guided-iac-walkthrough/`)
- Verbose documentation with explanations and doc links
- State uncertainty explicitly when not certain
- Save conversation progress to files as work proceeds
- `/finalize` at end of sessions to close out work properly
