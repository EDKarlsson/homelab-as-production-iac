# Concurrent Agent Coordination Workflow

Run this workflow whenever 2+ developers/agents may touch overlapping homelab services.

## Goal

Prevent unsafe concurrent changes by combining:
- branch-scoped task plans,
- local runtime lock files,
- mandatory pre-command guard checks.

This is optimized for **shared workstation / shared runner** coordination. It does not replace cross-machine distributed locking.

## Core Files and Scripts

- Task plan template: `.coord/task-plans/TEMPLATE.env`
- Service token map: `configs/coordination/service-map.csv`
- Service dependency map: `configs/coordination/service-deps.csv`
- Guard/check scripts:
  - `scripts/coord/task-plan-init.sh`
  - `scripts/coord/task-plan-validate.sh`
  - `scripts/coord/lock-acquire.sh`
  - `scripts/coord/lock-release.sh`
  - `scripts/coord/lock-status.sh`
  - `scripts/coord/guard.sh`

## Required Flow Per Branch

1. Start task in a dedicated worktree/branch (`.claude/commands/start-task.md`).
2. Initialize task plan (branch name + service scope + unstable services):

```bash
scripts/coord/task-plan-init.sh \
  --summary "Upgrade oauth2-proxy and validate SSO" \
  --services "oauth2-proxy,keycloak,ingress-nginx"
```

3. Validate plan consistency:

```bash
scripts/coord/task-plan-validate.sh
```

Validation enforces:
- branch token -> service mapping coverage,
- required unstable service coverage (including dependency map),
- branch/plan alignment.

4. Acquire locks before mutating commands:

```bash
scripts/coord/lock-acquire.sh --ttl-minutes 240
scripts/coord/lock-status.sh
```

5. Run commands through the guard wrapper (check runs every time):

```bash
scripts/coord/guard.sh terraform plan
scripts/coord/guard.sh terraform apply
scripts/coord/guard.sh kubectl apply -f kubernetes/apps/n8n
scripts/coord/guard.sh flux reconcile kustomization apps
scripts/coord/guard.sh ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-cluster.yml
```

6. Release locks when done or handing off:

```bash
scripts/coord/lock-release.sh --all
```

## Overlap and Deconflict Rules

- If two branches overlap on any unstable service or lock domain, the second lock acquire fails.
- Do not bypass conflicts for mutating commands; sequence work instead.
- Use PR merge order to serialize overlapping runtime verification.

Examples:
- `oauth2-proxy` + `keycloak` + `ingress-nginx` changes overlap on identity/network edge and must be serialized.
- `grafana` dashboard-only changes can run in parallel with media apps if lock domains do not overlap.

## Development Environment Testing (No Extra VM)

Because VM resources are limited:
- prefer namespace/release-name isolation in Kubernetes for test deployments,
- avoid parallel cluster-level infra mutations in overlapping domains,
- treat dependency-map services as unstable until post-merge smoke tests pass.

For AI/ML workloads that need GPU access, reuse the existing ComfyUI VM and gate passthrough work with coordination locks:
- include `comfyui` and `proxmox-infra` in `SERVICES`/`UNSTABLE_SERVICES`,
- acquire locks before any Terraform/Proxmox passthrough change,
- follow `docs/guides/comfyui-rtx3060-passthrough.md` to mount NVIDIA RTX 3060 PCI functions (`01:00.0` GPU, `01:00.1` audio example) into the VM and validate with `nvidia-smi`.

## Optional Shell Aliases

```bash
alias tf='scripts/coord/guard.sh terraform'
alias k='scripts/coord/guard.sh kubectl'
alias fx='scripts/coord/guard.sh flux'
alias ap='scripts/coord/guard.sh ansible-playbook'
```

Using these aliases enforces lock checks before each command invocation.
