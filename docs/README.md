# Documentation

## Project Planning

- [PROJECT-PLAN.md](./PROJECT-PLAN.md) — Phased roadmap from repo cleanup to app deployment
- [CICD-PLAN.md](./CICD-PLAN.md) — CI/CD implementation roadmap using homelab services

## Guides

Step-by-step walkthroughs for managing the Proxmox homelab with Terraform.

| # | Guide | Description |
|---|-------|-------------|
| ref | [Terraform Provider Setup](./guides/terraform-provider-setup.md) | Provider declaration, child module config |
| 1 | [Importing Existing Proxmox VMs](./guides/importing-existing-vms.md) | Bring manually-created VMs under Terraform |
| 2 | [Creating a VM Template](./guides/creating-vm-template.md) | Ubuntu 24.04 cloud image template with cloud-init |
| 3 | [Cloning K3s Node VMs](./guides/cloning-k3s-vms.md) | Clone template into k3s-ready VMs with static IPs |
| 4 | [Ansible K3s Provisioning](./guides/ansible-k3s-provisioning.md) | Install K3s with external PostgreSQL datastore |
| 5 | [FluxCD Bootstrap](./guides/fluxcd-bootstrap.md) | GitOps with Flux v2, SOPS+age secrets |
| 6 | [1Password Secrets Management](./guides/1password-secrets-management.md) | Unified secrets across CLI, Terraform, Ansible, K8s |
| 7 | [Terraform Remote State](./guides/terraform-remote-state.md) | PostgreSQL backend with advisory locking |
| 8 | [CI/CD Testing Workflow](./guides/ci-cd-testing-workflow.md) | GitHub Actions validation pipeline across Terraform, Ansible, Flux/K8s, scripts |
| 9 | [CI/CD Artifact Strategy](./guides/cicd-artifact-strategy.md) | Artifact scope, Nexus repository layout, and naming/versioning conventions |
| 10 | [GitOps Promotion and Rollback](./guides/gitops-promotion-and-rollback.md) | GitOps promotion flow, deployment verification gates, and rollback runbooks |
| 11 | [ComfyUI RTX 3060 Passthrough](./guides/comfyui-rtx3060-passthrough.md) | Proxmox GPU passthrough + guest Docker runtime setup for ComfyUI AI/ML workloads |
| 12 | [Concurrent Agent Coordination Workflow](./guides/concurrent-agent-coordination-workflow.md) | Branch/task-plan validation, local lock files, and guarded command execution for overlapping service changes |

See also: [Future Guides Roadmap](./guides/future-guides-roadmap.md)

## Architecture

- [Cluster Topology & Hardware](./architecture/pve-node-spec-config.md) — Node specs and resource allocation
- [Hardware Infrastructure](./architecture/hardware-infrastructure.md) — Physical hardware overview
- [Architecture Diagram](./architecture/homelab-architecture.drawio) — Visual overview (draw.io)

## Reference

Operational reference documents covering patterns, procedures, and troubleshooting.

- [Technical Gotchas](./reference/technical-gotchas.md) — Confirmed issues with known fixes across the stack
- [App Deployment Patterns](./reference/app-deployment-patterns.md) — HelmRelease vs raw manifests, ingress, storage patterns
- [Deployment Troubleshooting](./reference/deployment-troubleshooting.md) — Common deployment issues and resolutions
- [1Password Integration](./reference/1password-integration.md) — Connect server, Terraform, Ansible, ESO patterns
- [Environment Variables](./reference/environment-variables.md) — Env file architecture, credential flow, secrets management
- [Flux GitOps Patterns](./reference/flux-gitops-patterns.md) — Kustomization structure, dependency chains, reconciliation
- [K3s Upgrade Procedure](./reference/k3s-upgrade-procedure.md) — Rolling upgrade playbook and version hop strategy
- [PostgreSQL HA](./reference/postgresql-ha.md) — Primary/standby replication, keepalived VIP, failover
- [Proxmox LXC Patterns](./reference/proxmox-lxc-patterns.md) — Docker-in-LXC, provisioning, keepalived VRRP
- [Storage: Longhorn](./reference/storage-longhorn.md) — Distributed block storage setup and configuration
- [Tailscale Kubernetes](./reference/tailscale-kubernetes.md) — Tailscale operator, dual ingress, `*.ts.net` TLS
- [AI and LLM Information](./reference/ai-and-llm-information.md) — Claude Code setup, MCP servers, skills
- [MCP Kubernetes Deployment Strategy](./reference/mcp-kubernetes-deployment-strategy.md) — Which MCP servers to centralize in-cluster and how to auto-configure agent connections
- [CI/CD Ops Checklist](./reference/cicd-ops-checklist.md) — Save-for-tomorrow setup and validation checklist for CI/CD operations
- [Contributing & Practices](./reference/CONTRIBUTING.md) — Git workflow, tools, conventions
- [Changelog](./CHANGELOG.md) — Session-by-session change history

## Analysis

Audit reports and setup guides from analysis sessions.

- [Overnight Audit (2026-02-18)](./analysis/overnight-audit-2026-02-18.md) — K8s manifest audit, app recommendations, MCP utilization
- [Homepage Widget Setup](./analysis/homepage-setup-guide.md) — Step-by-step guide for configuring Homepage API tokens

## Blog Series

The Substack series documenting this project lives in its own repository:

**[homelab-as-production](https://github.com/homelab-admin/homelab-as-production)** — "Homelab as Production: AI-Assisted Infrastructure from Zero to GitOps"

17 posts covering the full build: Terraform, FluxCD, platform services, SSO, secrets, CI/CD, GitLab, security scanning, and the AI-assisted workflow. First draft complete as of 2026-02-26.

## Archive

Preserved but no longer actively maintained:

- [standards/](./archive/standards/) — AI-generated standards docs (10 files, 2024-01-15)
- [memory-bank/](./archive/memory-bank/) — Cline/Windsurf context files (superseded by Claude memory)
- [ai-generated/](./archive/ai-generated/) — AI-generated security audit report
