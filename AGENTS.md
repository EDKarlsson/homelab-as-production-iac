# Repository Guidelines

## Project Scope & Architecture
This repo manages a Proxmox-based homelab end-to-end: Terraform provisions infrastructure, Ansible configures hosts, and FluxCD reconciles Kubernetes manifests. Per `docs/PROJECT-PLAN.md`, Phases 0-3 are complete; the stack includes K3s (3 servers + 5 agents), PostgreSQL HA with keepalived VIP failover, platform controllers, and active app resources (with `jackett` and `docmost` kept disabled).

Flux ordering matters: `platform-controllers -> platform-configs -> apps`, with monitoring layers reconciled separately (`clusters/homelab/*.yaml`). Keep dependency safety in mind when adding new CRDs/controllers.

## Project Structure & Module Organization
- `infrastructure/`: Terraform root + modules (`k3s`, `pg-ha`, `op-connect`, `pve`).
- `ansible/`: inventories, group vars, and playbooks (including PG backup automation).
- `kubernetes/`: Flux-managed manifests (`apps/`, `platform/controllers/`, `platform/configs/`, `platform/monitoring/`).
- `clusters/homelab/`: Flux Kustomization entrypoints and reconciliation graph.
- `scripts/`: operational tooling (`k8s/validate.sh`, `k3s-verify.sh`, bootstrap and helper scripts).
- `docs/`: source of truth for roadmap, architecture, troubleshooting, and version tracking.

## Build, Test, and Development Commands
- `source .env.d/terraform.env` before infra operations.
- `terraform -chdir=infrastructure init && terraform -chdir=infrastructure plan`
- `ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-cluster.yml --forks=1`
- `bash scripts/k8s/validate.sh` (kustomize + kubeconform + Flux schema checks).
- `bash scripts/k8s/k3s-verify.sh --quick` (or full run for cluster-impacting changes).
- `pre-commit run --all-files` (terraform fmt/validate/tflint hooks).

## Coding Style & Naming Conventions
- Terraform: canonical formatting via hooks; resource IDs use underscores, VM names use hyphens.
- Keep YAML manifests explicit and composable; follow existing app patterns in `docs/reference/flux-gitops-patterns.md`.
- Prefer pinned versions over `:latest`; if using floating tags, document rationale.

## Testing, Docs, and PR Requirements
- Run validation commands above before PR.
- For infra/platform/app changes, update relevant docs: `docs/PROJECT-PLAN.md`, `docs/CHANGELOG.md`, and `docs/reference/version-matrix.md` when versions/features change.
- Record notable incidents/fixes in `docs/reference/technical-gotchas.md`.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), open PRs to `main`, and include scope, risk, rollback, and verification evidence.

## Security & Configuration Tips
- Never commit secrets, kubeconfigs, or generated env outputs.
- Secrets must come from 1Password Connect/External Secrets, not hardcoded manifests.
- Be careful with cloud-init/template changes in live environments; some updates can force VM replacement.
