# Infrastructure Guides

Step-by-step walkthroughs for managing the Proxmox homelab with Terraform (bpg/proxmox provider v0.95.0).

## Reference

- [Terraform Provider Setup](./terraform-provider-setup.md) — Provider declaration, child module configuration, passing variables and outputs between modules

## Guides

| # | Guide | Description |
|---|---|---|
| 1 | [Importing Existing Proxmox VMs](./importing-existing-vms.md) | Bring manually-created VMs under Terraform management |
| 2 | [Creating a Ubuntu 24.04 VM Template](./creating-vm-template.md) | Download cloud image, create a reusable template with cloud-init support |
| 3 | [Cloning k3s Node VMs from Template](./cloning-k3s-vms.md) | Clone the template into k3s-ready VMs with cloud-init, NFS, and static IPs |
| 4 | [Ansible K3s Provisioning](./ansible-k3s-provisioning.md) | Install K3s on cloned VMs with Ansible, external PostgreSQL datastore |
| 5 | [FluxCD Bootstrap](./fluxcd-bootstrap.md) | Bootstrap Flux v2 for GitOps, SOPS+age secrets, cert-manager, ingress-nginx |
| 6 | [1Password Secrets Management](./1password-secrets-management.md) | Unified secrets management across CLI, Terraform, Ansible, Kubernetes (ESO) |
| 7 | [Terraform Remote State with PostgreSQL](./terraform-remote-state.md) | Migrate from local to pg backend, 2-phase deployment, advisory locking |
| 8 | [CI/CD Testing Workflow](./ci-cd-testing-workflow.md) | GitHub Actions validation across Terraform, Ansible, Flux/K8s, and scripts |
| 9 | [CI/CD Artifact Strategy and Nexus Layout](./cicd-artifact-strategy.md) | Artifact scope, Nexus repository topology, and naming/version conventions |
| 10 | [GitOps Promotion and Rollback Workflow](./gitops-promotion-and-rollback.md) | Promotion model, deployment gates, and rollback playbooks |
| 11 | [ComfyUI RTX 3060 Passthrough](./comfyui-rtx3060-passthrough.md) | Proxmox IOMMU/VFIO setup and VM GPU passthrough validation for AI/ML workloads |
| 12 | [Concurrent Agent Coordination Workflow](./concurrent-agent-coordination-workflow.md) | Branch/task-plan validation, local lock files, and guarded command execution for overlapping service changes |
| 13 | [Slack + GitHub Workflows — Overview](./slack-gh-workflows-overview.md) | Analysis of 10 integration patterns; top 3 selected based on existing infrastructure fit |
| 14 | [Workflow 1: Prometheus Alert → GitHub Issue](./slack-gh-workflow-1-alert-to-issue.md) | n8n bridge: AlertManager webhook → deduplicated GitHub issue → Slack link |
| 15 | [Workflow 2: Scheduled Maintenance Windows](./slack-gh-workflow-2-scheduled-maintenance.md) | GitHub Actions cron checks for cert expiry, K3s version lag, and backup health |
| 16 | [Workflow 3: Capacity Planning Alerts](./slack-gh-workflow-3-capacity-planning.md) | Sustained-pressure PrometheusRules → n8n → GitHub issue with metrics snapshot |

## Reports & Analysis

- [Terraform Module Audit Report](./terraform-module-audit.md) — 23 issues found across all modules (9 ERROR, 8 WARNING, 5 INFO)
- [Future Guides Roadmap & Script Improvements](./future-guides-roadmap.md) — 13 proposed guides and improvements for 12 scripts

## Environment Quick Reference

| Item | Value |
|---|---|
| Provider | `bpg/proxmox` v0.95.0 |
| Proxmox nodes | node-01, node-02, node-03, node-04, node-05 |
| NFS storage | `Proxmox_NAS` (10.0.0.161:/volume1/proxmox) — has `import`, `snippets`, `images` |
| Local storage | `local-lvm` (LVM-thin) — has `images` only |
| Credentials | `.env.saved` (source before running API commands) |
