---
title: Ansible Patterns
description: Ansible patterns and lint compliance for the homelab K3s provisioning playbooks, including 1Password lookups, idiomatic task modules, and ansible-lint rules
published: true
date: 2026-02-25
tags:
  - ansible
  - 1password
  - lint
  - k3s
  - provisioning
  - secrets
---

Ansible patterns used in the homelab K3s provisioning playbooks. Covers idiomatic task patterns for ansible-lint compliance, the `community.general.onepassword` lookup for secret injection at playbook runtime, and common gotchas.

## 1Password Lookup in group_vars

The `community.general.onepassword` lookup plugin retrieves secrets from 1Password at playbook evaluation time using the `op` CLI. This replaces the previous pattern of falling back to vault-encrypted variables.

### Installation

Add the collection to `ansible/requirements.yml`:

```yaml
collections:
  - name: community.general
    version: ">=8.1.0"
```

Install before running playbooks:

```bash
uv run ansible-galaxy collection install -r ansible/requirements.yml
```

### Usage in group_vars

```yaml
# ansible/inventory/group_vars/k3s_cluster.yml
k3s_token: "{{ lookup('community.general.onepassword', 'homelab-k3s-cluster', field='token', vault='Homelab') }}"
```

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| First positional arg | Item title in 1Password |
| `field` | Custom text field name on the item |
| `section` | (Optional) Section name if the field is in a section |
| `vault` | Vault name to search (avoids cross-vault ambiguity) |

**Lazy evaluation:** Variables in `group_vars` defined with lookups are evaluated lazily -- the `op` CLI is not called until the variable is first referenced in a task. This means the lookup only happens when a task actually uses the variable, not at inventory load time.

**Prerequisites:** The `op` CLI must be authenticated when the playbook runs. With the 1Password SSH agent active (`SSH_AUTH_SOCK=~/.1password/agent.sock`), the CLI session is typically active. Verify with `op account list`.

**Connect mode conflict:** The `op` CLI lookup uses the personal account mode. If `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` are set in the shell environment (for Terraform Connect mode), unset them before running Ansible:

```bash
env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN uv run ansible-playbook ...
```

### Comparison: Lookup vs Vault Fallback

The previous pattern used `ansible-vault` encrypted vars with a `| default()` fallback:

```yaml
# Old pattern (vault fallback)
k3s_token: "{{ vault_k3s_token | default('') }}"
```

The `community.general.onepassword` lookup is preferred because:

- No vault password required during playbook runs
- Secrets rotate automatically (no re-encryption needed)
- Single source of truth (1Password)
- Variables remain readable in `group_vars` files

## Ansible Lint Compliance

The homelab playbooks follow `ansible-lint` rules. Key patterns that trip up lint and their solutions:

### no-relative-paths

**Rule:** Template file paths must be absolute (derived from `playbook_dir`), not relative strings.

```yaml
# Incorrect -- fails no-relative-paths
- name: Copy registries template
  ansible.builtin.template:
    src: "templates/k3s-registries.yaml.j2"   # relative path

# Correct -- use playbook_dir | dirname
- name: Copy registries template
  ansible.builtin.template:
    src: "{{ playbook_dir | dirname }}/templates/k3s-registries.yaml.j2"
```

The `| dirname` filter is needed because `playbook_dir` points to the playbook file's directory (e.g., `ansible/playbooks/`), but `templates/` lives at `ansible/templates/`. Using `dirname` goes up one level to `ansible/`.

### command-instead-of-module

**Rule:** Use `ansible.builtin` modules instead of shell commands when a dedicated module exists.

| Instead of | Use |
|------------|-----|
| `shell: curl -fsSL <url> \| sh` | `get_url` + `shell` (see below) |
| `shell: ls -t /path/ \| tail -1` | `ansible.builtin.find` |
| `command: systemctl status <svc>` | `ansible.builtin.service` with `state:` |
| `shell: mkdir -p /path` | `ansible.builtin.file` with `state: directory` |

### risky-shell-pipe

**Rule:** Shell commands with pipes to `sh`/`bash` are flagged as risky.

The `curl | sh` pattern fails both `command-instead-of-module` (should use `get_url`) and `risky-shell-pipe` (piping to shell). The combined fix:

```yaml
# Incorrect -- fails both rules
- name: Install k3s
  ansible.builtin.shell: "curl -fsSL https://get.k3s.io | sh -s - server"
  args:
    executable: /bin/bash

# Correct -- download first, then execute local file
- name: Download k3s install script
  ansible.builtin.get_url:
    url: "https://get.k3s.io"
    dest: "/tmp/k3s-install.sh"
    mode: "0755"

- name: Install k3s
  ansible.builtin.shell: "/tmp/k3s-install.sh server"
  args:
    executable: /bin/bash
```

This satisfies both rules: `get_url` handles the HTTP download (correct module), and `shell` executes a local file without a pipe.

### Idiomatic File Discovery

Replace shell-based file listing with `ansible.builtin.find`:

```yaml
# Incorrect -- uses shell for file discovery
- name: Get latest log file
  ansible.builtin.shell: "ls -t /var/log/app/ | tail -1"
  register: latest_log

# Correct -- use find module
- name: Get latest log file
  ansible.builtin.find:
    paths: "/var/log/app/"
    patterns: "*.log"
    age: -1d
  register: found_logs

- name: Use latest log file
  ansible.builtin.debug:
    msg: "Latest: {{ (found_logs.files | sort(attribute='mtime') | last).path }}"
```

## Playbook Structure

### Inventory Layout

```
ansible/
  inventory/
    k3s.yml                    # Inventory file (static IPs, SSH config)
    group_vars/
      k3s_cluster.yml          # Shared vars including 1Password lookups
      k3s_server.yml           # Server-specific vars
      k3s_agent.yml            # Agent-specific vars
  playbooks/
    k3s-cluster.yml            # Site playbook (servers + agents)
    k3s-servers.yml            # Server provisioning
    k3s-agents.yml             # Agent provisioning
    k3s-upgrade.yml            # Rolling upgrade
    k3s-registry-mirrors.yml   # Containerd registry mirror config
    pg-backup.yml              # PostgreSQL backup automation
    pg-create-db.yml           # Reusable DB bootstrap (create DB + user + pg_hba on primary + standby)
  templates/
    k3s-registries.yaml.j2     # Registry mirror config template
    pg-backup.sh.j2            # Backup script template
  requirements.yml             # Collection requirements (community.general)
```

**Critical:** `group_vars/` must be adjacent to the inventory file (`inventory/group_vars/`). Placing it as a sibling of `inventory/` (e.g., `ansible/group_vars/`) causes Ansible to silently ignore it -- no error is raised, variables just never load.

### Running Playbooks

```bash
# Always use uv run (bare ansible-playbook not in PATH)
# Always use --forks=1 with 1Password SSH agent (parallel connections overwhelm approval dialog)
uv run ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/k3s-cluster.yml --forks=1

# Install collection requirements first
uv run ansible-galaxy collection install -r ansible/requirements.yml

# Lint before committing
uv run ansible-lint ansible/playbooks/k3s-cluster.yml
```

## Check Mode Behavior

`ansible-lint` itself runs tasks in check mode when validating playbooks. Tasks that use `until` loops with shell commands will exhaust retries in check mode because:

1. Check mode skips actual command execution
2. The command returns empty stdout
3. The `until` condition (which checks stdout content) never becomes true
4. The loop retries until `retries` is exhausted and fails

This is expected behavior in check mode and is NOT a real failure. In production playbook runs (without `--check`), `until` loops work correctly. Document this in playbooks or add lint skip annotations for affected tasks:

```yaml
- name: Wait for k3s to be ready
  ansible.builtin.shell: k3s kubectl get nodes
  register: nodes_output
  until: "'Ready' in nodes_output.stdout"
  retries: 30
  delay: 10
  changed_when: false
  tags:
    - skip_ansible_lint  # check mode exhausts retries; works fine in production
```

## Key Files

| File | Purpose |
|------|---------|
| `ansible/requirements.yml` | Collection requirements (`community.general >= 9.0.0`) |
| `ansible/inventory/group_vars/k3s_cluster.yml` | Cluster-wide variables including 1Password lookups |
| `ansible/playbooks/k3s-cluster.yml` | Site playbook |
| `ansible/playbooks/k3s-upgrade.yml` | Rolling upgrade (serial: 1, drain/upgrade/uncordon) |
| `ansible/playbooks/pg-backup.yml` | PostgreSQL backup script deployment |
| `ansible/playbooks/pg-create-db.yml` | Reusable playbook for bootstrapping PostgreSQL databases (create DB + user + pg_hba on both primary and standby) |
| `ansible/templates/k3s-registries.yaml.j2` | Containerd registry mirror configuration |

## Gotchas

| Area | Gotcha | Fix |
|------|--------|-----|
| Execution | `ansible-playbook` not in PATH -- only available via `uv run` | Always prefix with `uv run ansible-playbook` |
| Parallelism | 1Password SSH agent requires user approval per connection; parallel forks overwhelm the approval dialog | Use `--forks=1` for all playbook runs against homelab hosts |
| Jinja2 + Bash | `${#array[@]}` is interpreted as a Jinja2 comment start (`{# ... #}`) in `.j2` templates | Wrap Bash-native array syntax in `{% raw %}...{% endraw %}` blocks |
| Lookups in check mode | `community.general.onepassword` lookup still calls `op` CLI in check mode; requires active `op` session | Ensure `op` is authenticated before running `--check` playbooks |
| `playbook_dir` in inventory | `playbook_dir` is only available during playbook execution, not at inventory load time | Use `inventory_dir` for paths relative to the inventory file |
| `partial-become` lint rule | `become_user` at the task level requires `become: true` at the SAME task level -- ansible-lint rule `partial-become` enforces this even when `become: true` is set at play level. Tasks that set `become_user: postgres` without an explicit `become: true` on the same task fail lint. | Add `become: true` explicitly to every task that uses `become_user`; do not rely on play-level privilege escalation to satisfy the per-task check. |
| CI collection install | The GitHub Actions CI workflow hardcodes the `ansible-galaxy collection install` arguments -- it does NOT read `ansible/requirements.yml`. Adding a collection to `requirements.yml` only affects local `ansible-galaxy collection install -r ansible/requirements.yml` runs, not CI. | Add new collections directly to the `ansible-galaxy collection install` line in `.github/workflows/ci-testing.yml`. Treat `requirements.yml` as developer documentation; `ci-testing.yml` is the authoritative collection list for CI. |
| Handlers skip on abort | Ansible handlers are skipped when a play aborts on task failure -- handlers only fire if the play completes (or `meta: flush_handlers` is reached). If a critical post-step like `update-ca-certificates` is registered as a handler but the play aborts beforehand, the handler never runs. | For critical, order-dependent post-processing, use an inline follow-up task with `when: prev_task.changed` instead of a handler. This runs immediately after the triggering task regardless of play outcome. |
