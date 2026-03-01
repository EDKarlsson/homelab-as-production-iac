---
title: K3s Upgrade Procedure
description: Rolling upgrade procedure for the K3s cluster including version skew policy compliance and the Ansible playbook pattern
published: true
date: 2026-02-18
tags:
  - k3s
  - kubernetes
  - upgrade
  - ansible
  - rolling-update
---

Rolling upgrade procedure for the K3s cluster, including version skew policy compliance and the Ansible playbook pattern.

## Version Skew Policy

Kubernetes enforces a version skew policy: the control plane and kubelets may differ by at most one minor version. Multi-minor upgrades must be performed as sequential single-minor hops.

For the homelab cluster, the upgrade from v1.28.3+k3s1 to v1.32.12+k3s1 required 4 sequential hops:

```
v1.28.3+k3s1 -> v1.29.12+k3s1 -> v1.30.10+k3s1 -> v1.31.8+k3s1 -> v1.32.12+k3s1
```

Each hop targets the latest patch release of the next minor version. Using the latest patch within each minor version ensures security fixes are included.

## Rolling Upgrade Pattern

The upgrade playbook (`ansible/playbooks/k3s-upgrade.yml`) follows a 5-phase pattern:

### Phase 1: Pre-flight Checks

- Record the current K3s version across all nodes
- Verify all nodes report `Ready` status
- Check for `CrashLoopBackOff` pods (warning, not blocking)

### Phase 2: PostgreSQL Backup

- Dump the K3s database on the PostgreSQL VM before any changes
- Backups stored at `/var/backups/k3s-upgrade/` with version and timestamp

### Phase 3: Upgrade Servers (serial: 1)

For each server node, one at a time:

1. **Drain** the node (`kubectl drain --ignore-daemonsets --delete-emptydir-data --timeout=120s`)
2. **Install** the target K3s version using the official installer script
3. **Wait** for the K3s service to be active and the node to report Ready
4. **Uncordon** the node
5. **Pause** 30 seconds before proceeding to the next server

Drain and uncordon commands are delegated to the first server node (which runs kubectl).

### Phase 4: Upgrade Agents (serial: 1)

Same drain/install/uncordon pattern as servers, but:

- Uses `K3S_URL` and `K3S_TOKEN` environment variables for the installer
- The K3s agent service name is `k3s-agent` (not `k3s`)
- Node readiness checks are delegated to a server node (agents do not run kubectl)

### Phase 5: Post-upgrade Verification

- Verify all nodes report the target version
- Confirm all nodes are Ready
- Check system pod health in `kube-system` namespace

## Usage

Run the playbook once per hop, passing the target version as an extra variable:

```bash
export SSH_AUTH_SOCK=~/.1password/agent.sock

# Hop 1: v1.28 -> v1.29
ansible-playbook -i inventory/k3s.yml playbooks/k3s-upgrade.yml \
  -e k3s_version=v1.29.12+k3s1

# Hop 2: v1.29 -> v1.30
ansible-playbook -i inventory/k3s.yml playbooks/k3s-upgrade.yml \
  -e k3s_version=v1.30.10+k3s1

# Continue for each minor version...
```

The `k3s_version` variable must be passed at runtime via `-e` for each hop. Do not rely on the `group_vars` default during upgrades, as the default reflects the final target version.

## Idempotency

Each task checks whether the node is already at the target version and skips if so. This means:

- Re-running the playbook after a partial failure resumes where it left off
- Nodes already upgraded are not drained or reinstalled
- The playbook is safe to run multiple times for the same version hop

## Flux Compatibility

K3s version and Flux version must be compatible. Flux v2.5+ requires Kubernetes >= 1.32, while Flux v2.3.x supports Kubernetes 1.28+. After upgrading K3s to v1.32, newer Flux versions become available.

## Key Files

| File | Purpose |
|------|---------|
| `ansible/playbooks/k3s-upgrade.yml` | Rolling upgrade playbook |
| `ansible/inventory/k3s.yml` | Cluster inventory (node IPs, SSH config) |
| `ansible/inventory/group_vars/k3s_cluster.yml` | Default K3s version and cluster variables |
