# Ansible

Playbooks for K3s cluster provisioning, upgrades, and Proxmox host maintenance.

## Prerequisites

### 1. Install Galaxy collections

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Installs:
- `community.general` — provides the `onepassword` lookup plugin (uses `op` CLI)
- `artis3n.tailscale` — Tailscale role for PVE hosts (`pve.yml`)
- `onepassword.connect` — 1Password Connect API collection (for future CI use)

### 2. Set up 1Password CLI

Secrets are fetched at playbook runtime via the `op` CLI:

```bash
# Verify op is in PATH and authenticated
op whoami
```

The 1Password desktop app must be running (biometric session). The lookup happens
transparently when Ansible evaluates variables in `group_vars/k3s_cluster.yml`.

**What's fetched:**

| Variable | 1Password Item | Section | Field |
|----------|---------------|---------|-------|
| `k3s_cluster_token` | `homelab-k3s-cluster` | `cluster` | `server-token` |
| `postgres_password` | `homelab-k3s-cluster` | `database` | `password` |

### 3. Set up SSH agent

K3s playbooks connect as `k3sadmin` using the key stored in 1Password:

```bash
export SSH_AUTH_SOCK=~/.1password/agent.sock
```

This is set automatically if `.env.d/base.env` is sourced.

---

## Running playbooks

```bash
# Always use --forks=1 — 1Password SSH agent prompts per-connection
uv run ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-cluster.yml --forks=1

# Upgrade K3s (rolling, drain/uncordon per node)
uv run ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-upgrade.yml --forks=1

# PostgreSQL HA backups
uv run ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/pg-backup.yml --forks=1

# Proxmox host maintenance (separate inventory, no SSH agent required)
uv run ansible-playbook -i ansible/inventory/inventory.yml ansible/playbooks/pve.yml
```

### Bootstrap override (no 1Password)

For initial provisioning before `op` is configured, pass secrets directly:

```bash
uv run ansible-playbook ... \
  -e k3s_cluster_token="$(op item get homelab-k3s-cluster --field server-token --reveal)" \
  -e postgres_password="$(op item get homelab-k3s-cluster --field password --reveal)"
```

---

## Future: CI/CD with 1Password Connect

For non-interactive runs (GitHub Actions, scheduled jobs), the `onepassword.connect`
collection can replace the `op` CLI approach:

```bash
export OP_CONNECT_HOST=https://op-connect.homelab.ts.net
export OP_CONNECT_TOKEN=$(op item get op-connect-ansible --field token --reveal)
```

Then switch lookups to `onepassword.connect.field_value` in group_vars.
Connect server is already running at `op-connect.homelab.ts.net` (HA VIP, keepalived failover).
