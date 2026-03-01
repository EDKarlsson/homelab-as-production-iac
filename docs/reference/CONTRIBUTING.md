---
title: Contributing and Project Practices
description: Git workflow, pre-commit hooks, secrets management, Terraform conventions, and tooling used in this project
published: true
date: 2026-02-18
tags:
  - contributing
  - git
  - terraform
  - conventions
  - tooling
  - pre-commit
---

Actual practices followed in this project. For archived aspirational standards, see `docs/archive/standards/`.

## Git Workflow

- **Branching:** feature branches off `main` (`feat/`, `fix/`, `chore/`)
- **Commits:** conventional commits (`feat:`, `fix:`, `chore:`, `docs:`)
- **PRs:** all changes go through PRs against `main` via `gh pr create`
- **Merging:** squash merge on GitHub, delete branch after merge

## Parallel Work Coordination

When 2+ developers/agents are active, use the coordination workflow in `docs/guides/concurrent-agent-coordination-workflow.md`.

- Create/update a branch-scoped task plan via `scripts/coord/task-plan-init.sh`
- Validate branch/service/unstable-service alignment via `scripts/coord/task-plan-validate.sh`
- Acquire local runtime locks via `scripts/coord/lock-acquire.sh` before mutating commands
- Run mutating commands through `scripts/coord/guard.sh` so lock checks happen every invocation
- Release locks via `scripts/coord/lock-release.sh --all` when done

## Versioning

This project uses a semver-based tagging convention: `v0.<PR#>.0`, where the minor version corresponds to the GitHub PR number that introduced the change. Tags are created on the `main` branch after merging.

## Pre-commit Hooks

Configured in `.pre-commit-config.yaml` (antonbabenko/pre-commit-terraform v1.105.0):

```bash
pre-commit run --all-files   # Run all hooks
```

| Hook | What it does |
|------|-------------|
| `terraform_fmt` | Enforces canonical formatting on all `.tf` files |
| `terraform_validate` | Runs `terraform validate` in each module directory |
| `terraform_tflint` | Lints with tflint v0.61.0 |

## Secrets Management

- **All secrets** live in 1Password (Homelab vault)
- **Terraform** reads credentials via 1Password Connect data sources (no `TF_VAR_` secrets in env)
- **SSH keys** managed by 1Password SSH agent (`~/.1password/agent.sock`)
- **Environment files:** `.env.d/terraform.env` contains only the Connect token and non-secret defaults

## Terraform Conventions

- **Provider:** bpg/proxmox v0.95.0 + 1Password/onepassword v3.2.1
- **Root module:** `infrastructure/main.tf` — providers, data sources, child module calls
- **Child modules:** `infrastructure/modules/<name>/` — self-contained with own `providers.tf`
- **Naming:** resource names use underscores (`k3s_servers`), VM names use hyphens (`homelab-server-*`)
- **State:** PostgreSQL backend at `10.0.0.45` (`PG_CONN_STR` env var); VIP `10.0.0.44` available (see [postgresql-ha.md](./postgresql-ha.md))

## Cloud-init Templates

- Extension: `.tftpl` (not `.tpl`) for IDE support
- Location: `infrastructure/modules/k3s/cloud-configs/`
- Always include `qemu-guest-agent` in packages
- Use `defer: true` on `write_files` entries with custom `owner:`
- **Never modify templates for running VMs** — any content change forces snippet replacement → `user_data_file_id` change → VM destruction and recreation. Cloud-init only runs at first boot.

## QEMU Guest Agent

The bpg/proxmox provider reads network interfaces from the QEMU guest agent during every `plan`/`apply`. Without a running agent, each VM refresh hangs until timeout.

| Setting | Value | Why |
|---------|-------|-----|
| `agent.enabled` | `true` | Tells Proxmox to attach the virtio-serial channel |
| `agent.timeout` | `2m` | Agent responds in <1s when running; 2m is a safe ceiling |
| `qemu-guest-agent` package | in cloud-init `packages:` | Installs the agent binary |
| `systemctl start` | manual or Ansible | Ubuntu 24.04 installs but does NOT auto-start it |

**If `terraform plan` is slow (>30s):** check the agent is running on all VMs:

```bash
scripts/k8s/k3s-ssh.sh all 'systemctl is-active qemu-guest-agent'
# Fix: scripts/k8s/k3s-ssh.sh all 'sudo systemctl enable --now qemu-guest-agent'
```

## Tools

| Tool | Location | Purpose |
|------|----------|---------|
| `terraform` | system PATH | Infrastructure provisioning |
| `kubectl` | `/usr/local/bin/kubectl` | Cluster access (standalone, not K3s-bundled) |
| `gh` | `~/.local/bin/gh` | GitHub CLI (authenticated as homelab-admin) |
| `tflint` | `~/.local/bin/tflint` | Terraform linting |
| `uv` | system PATH | Python package management (not `pip`) |
| `pre-commit` | venv | Git hooks |
