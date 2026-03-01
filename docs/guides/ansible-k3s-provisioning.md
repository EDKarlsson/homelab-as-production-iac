# Guide: Provisioning K3s with Ansible

This guide covers how to install and configure a K3s cluster on the VMs created by Terraform
(see [Cloning k3s Node VMs](./cloning-k3s-vms.md)) using Ansible. After completing this guide,
you will have a running K3s cluster with 5 server nodes, 5 agent nodes, and an external PostgreSQL
datastore.

## Prerequisites

- VMs created and running (see [Cloning k3s Node VMs](./cloning-k3s-vms.md))
- Ansible >= 2.15 installed on your workstation
- SSH access to all K3s VMs (configured by cloud-init in the cloning guide)
- An external PostgreSQL database ready and accessible from the K3s VMs
- A shared K3s token (a random string you choose — used by all nodes)

## Key documentation

| Topic | URL |
|---|---|
| K3s server CLI flags | https://docs.k3s.io/cli/server |
| K3s agent CLI flags | https://docs.k3s.io/cli/agent |
| K3s datastore (external DB) | https://docs.k3s.io/datastore |
| K3s HA with external DB | https://docs.k3s.io/datastore/ha |
| K3s architecture | https://docs.k3s.io/architecture |
| k3s-io/k3s-ansible (official) | https://github.com/k3s-io/k3s-ansible |
| Ansible playbook best practices | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_best_practices.html |
| K3s releases | https://github.com/k3s-io/k3s/releases |

---

## Background: installation approaches

There are three common approaches for installing K3s via Ansible:

| Approach | Pros | Cons |
|----------|------|------|
| **Official k3s-ansible** ([k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)) | Maintained by K3s team, handles HA etcd | Optimized for embedded etcd, not external datastores |
| **Community role** ([PyratLabs/ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s)) | Supports external datastores, very configurable | Extra dependency to manage |
| **Manual Ansible tasks** | Full control, no role dependencies | More code to write and maintain |

**Recommendation for this project:** Manual Ansible tasks. Your cluster uses an **external PostgreSQL
datastore**, which the official k3s-ansible role doesn't directly support (it targets embedded etcd).
Manual tasks give you explicit control over the bootstrap sequence and flags.

---

## Step 1: Generate Ansible inventory from Terraform

**What you're doing:** Creating an Ansible inventory file that lists your K3s server and agent VMs
with their IP addresses. You can generate this from Terraform outputs or write it by hand.

### Option A: Static inventory (simplest for a homelab)

Create `ansible/inventory/k3s-cluster.yml` with the actual IPs assigned to your VMs:

```yaml
# ansible/inventory/k3s-cluster.yml
all:
  children:
    k3s_servers:
      hosts:
        homelab-server-node-02:
          ansible_host: 10.0.0.50
          k3s_server_init: true       # First server only
        homelab-server-node-03:
          ansible_host: 10.0.0.51
        homelab-server-node-04:
          ansible_host: 10.0.0.52
        homelab-server-node-01:
          ansible_host: 10.0.0.53
        homelab-server-node-05:
          ansible_host: 10.0.0.54
      vars:
        k3s_role: server

    k3s_agents:
      hosts:
        homelab-agent-node-02:
          ansible_host: 10.0.0.60
        homelab-agent-node-03:
          ansible_host: 10.0.0.61
        homelab-agent-node-04:
          ansible_host: 10.0.0.62
        homelab-agent-node-01:
          ansible_host: 10.0.0.63
        homelab-agent-node-05:
          ansible_host: 10.0.0.64
      vars:
        k3s_role: agent

    k3s_cluster:
      children:
        k3s_servers:
        k3s_agents:
      vars:
        ansible_user: <your-vm-username>
        ansible_connection: ssh
        ansible_private_key_file: ~/.ssh/homelab/k3s/k3s_ed25519
        ansible_become: true
```

Replace `<your-vm-username>` with the user you configured in your cloud-init template.

The IP addresses above match the `local.k3s_server_ips` and `local.k3s_agent_ips` maps defined
in `infrastructure/modules/k3s/k3s-cluster.tf`.

### Option B: Generate from Terraform outputs

Add a `local_file` resource to your Terraform config that templates the inventory:

```hcl
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/ansible-inventory.yml.tpl", {
    servers = module.k3s.k3s_servers
    agents  = module.k3s.k3s_agents
    ssh_user = var.vm_username
  })
  filename = "${path.module}/../ansible/inventory/k3s-cluster.yml"
}
```

This regenerates the inventory on every `terraform apply`. Practical for a homelab where the
infrastructure is relatively stable.

**Docs:**
- [Terraform local_file resource](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file)
- [Ansible inventory YAML format](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)

---

## Step 2: Create group variables

**What you're doing:** Defining shared configuration for all K3s nodes in Ansible group_vars files.

Create `ansible/group_vars/k3s_cluster.yml`:

```yaml
# ansible/group_vars/k3s_cluster.yml
---
# K3s version — check https://github.com/k3s-io/k3s/releases for latest stable
k3s_version: "v1.31.4+k3s1"

# Cluster networking
k3s_cluster_cidr: "10.42.0.0/16"
k3s_service_cidr: "10.43.0.0/16"
k3s_cluster_dns: "10.43.0.10"
k3s_cluster_domain: "cluster.local"

# External PostgreSQL datastore
k3s_datastore_endpoint: "postgres://k3s:{{ vault_k3s_db_password }}@10.0.0.45:5432/k3s"

# Cluster token — all nodes must use the same token
k3s_token: "{{ vault_k3s_token }}"

# First server IP (for agent nodes to join)
k3s_first_server_ip: "10.0.0.50"

# Components to disable
k3s_disable:
  - traefik       # We'll use ingress-nginx via Flux instead
  - servicelb     # We'll use MetalLB or kube-vip instead

# TLS Subject Alternative Names for the API server certificate
k3s_tls_san:
  - "homelab-k3s-api.homelab.local"
  - "10.0.0.50"
```

Create `ansible/group_vars/k3s_cluster/vault.yml` for secrets (encrypt with `ansible-vault`):

```yaml
# ansible/group_vars/k3s_cluster/vault.yml (encrypted)
---
vault_k3s_token: "your-random-cluster-token-here"
vault_k3s_db_password: "your-postgresql-password"
```

Encrypt it:

```bash
ansible-vault encrypt ansible/group_vars/k3s_cluster/vault.yml
```

**Docs:**
- [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/vault.html)
- [Group variables](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables)

### Alternative: 1Password Connect lookup (instead of ansible-vault)

If you prefer to store secrets in 1Password instead of encrypted vault files, use the
`community.general.onepassword` lookup plugin with Connect mode (requires `community.general`
v8.1.0+). This fetches secrets at runtime from your Connect server — no `op` CLI needed:

```bash
# Install the collection
ansible-galaxy collection install community.general

# Set connection vars
export OP_CONNECT_HOST="https://op-connect.homelab.ts.net"
export OP_CONNECT_TOKEN="<your-connect-token>"
```

Then replace the vault file with direct lookups in `group_vars/k3s_cluster.yml`:

```yaml
# ansible/group_vars/k3s_cluster.yml — 1Password variant
---
k3s_token: "{{ lookup('community.general.onepassword', 'K3s Cluster Token',
              field='password', vault='Homelab') }}"

k3s_datastore_endpoint: >-
  postgres://k3s:{{ lookup('community.general.onepassword', 'PostgreSQL K3s',
              field='password', vault='Homelab') }}@10.0.0.45:5432/k3s
```

No `--ask-vault-pass` needed — secrets come from 1Password instead of an encrypted file. The
tradeoff is that the Connect server must be reachable when running playbooks.

See [Guide 6: 1Password Secrets Management — Ansible Integration](./1password-secrets-management.md#part-4-ansible-integration)
for full details including tradeoffs between ansible-vault and 1Password.

---

## Step 3: Create the K3s server playbook

**What you're doing:** Writing an Ansible playbook that installs K3s in server mode on all 5
server nodes. The key detail is the **bootstrap sequence** — with an external PostgreSQL datastore,
all servers use the same flags.

Create `ansible/playbooks/k3s-servers.yml`:

```yaml
---
- name: Prepare K3s server nodes
  hosts: k3s_servers
  become: true
  gather_facts: true

  tasks:
    # ── Kernel prerequisites ──────────────────────────────────────
    - name: Disable swap permanently
      ansible.builtin.command: swapoff -a
      changed_when: false

    - name: Remove swap entry from fstab
      ansible.builtin.lineinfile:
        path: /etc/fstab
        regexp: '^\S+\s+\S+\s+swap\s+'
        state: absent

    - name: Load required kernel modules
      community.general.modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - br_netfilter
        - ip_vs
        - ip_vs_rr
        - ip_vs_wrr
        - ip_vs_sh
        - nf_conntrack

    - name: Persist kernel modules across reboots
      ansible.builtin.copy:
        dest: /etc/modules-load.d/k3s.conf
        content: |
          br_netfilter
          ip_vs
          ip_vs_rr
          ip_vs_wrr
          ip_vs_sh
          nf_conntrack
        mode: '0644'

    - name: Configure sysctl for Kubernetes networking
      ansible.posix.sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        sysctl_file: /etc/sysctl.d/k3s.conf
        reload: true
      loop:
        - { key: "net.bridge.bridge-nf-call-iptables", value: "1" }
        - { key: "net.bridge.bridge-nf-call-ip6tables", value: "1" }
        - { key: "net.ipv4.ip_forward", value: "1" }

    # ── K3s configuration ─────────────────────────────────────────
    - name: Create K3s config directory
      ansible.builtin.file:
        path: /etc/rancher/k3s
        state: directory
        mode: '0755'

    - name: Deploy K3s server configuration
      ansible.builtin.template:
        src: k3s-server-config.yaml.j2
        dest: /etc/rancher/k3s/config.yaml
        mode: '0600'

    # ── K3s installation ──────────────────────────────────────────
    - name: Download and install K3s
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION={{ k3s_version }} sh -s - server
      args:
        creates: /usr/local/bin/k3s
      environment:
        INSTALL_K3S_SKIP_START: "true"

    - name: Start K3s service
      ansible.builtin.systemd:
        name: k3s
        state: started
        enabled: true

    - name: Wait for K3s API to be available
      ansible.builtin.uri:
        url: "https://127.0.0.1:6443/healthz"
        validate_certs: false
      register: k3s_health
      until: k3s_health.status == 200
      retries: 30
      delay: 10

    # ── kubectl setup for the admin user ──────────────────────────
    - name: Create .kube directory for admin user
      ansible.builtin.file:
        path: "/home/{{ ansible_user }}/.kube"
        state: directory
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
        mode: '0700'

    - name: Copy kubeconfig for admin user
      ansible.builtin.copy:
        src: /etc/rancher/k3s/k3s.yaml
        dest: "/home/{{ ansible_user }}/.kube/config"
        remote_src: true
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
        mode: '0600'
  tags:
    - k3s-servers
```

Create the config template at `ansible/playbooks/templates/k3s-server-config.yaml.j2`:

```yaml
# {{ ansible_managed }}
# K3s Server Configuration — Asgard Cluster
token: {{ k3s_token }}
datastore-endpoint: {{ k3s_datastore_endpoint }}
node-name: {{ inventory_hostname }}
node-ip: {{ ansible_host }}
bind-address: {{ ansible_host }}
advertise-address: {{ ansible_host }}
tls-san:
{% for san in k3s_tls_san %}
  - {{ san }}
{% endfor %}
  - {{ ansible_host }}
  - {{ inventory_hostname }}
  - {{ inventory_hostname }}.homelab.local
{% for component in k3s_disable %}
disable:
  - {{ component }}
{% endfor %}
cluster-cidr: {{ k3s_cluster_cidr }}
service-cidr: {{ k3s_service_cidr }}
cluster-dns: {{ k3s_cluster_dns }}
cluster-domain: {{ k3s_cluster_domain }}
write-kubeconfig-mode: "0644"
secrets-encryption: true
```

**Important:** With an external PostgreSQL datastore, you do **not** need `--cluster-init` or
`--server` flags for server nodes. All servers connect directly to PostgreSQL and discover each
other through the shared datastore. The `--cluster-init` flag is **only for embedded etcd**.

**Docs:**
- [K3s server configuration file](https://docs.k3s.io/installation/configuration#configuration-file)
- [K3s HA with external DB](https://docs.k3s.io/datastore/ha)

---

## Step 4: Create the K3s agent playbook

**What you're doing:** Writing a playbook that installs K3s in agent mode on all 5 agent nodes.
Agents join the cluster by pointing to a server node's API endpoint.

Create `ansible/playbooks/k3s-agents.yml`:

```yaml
---
- name: Prepare K3s agent nodes
  hosts: k3s_agents
  become: true
  gather_facts: true

  tasks:
    # ── Same kernel prereqs as servers ────────────────────────────
    - name: Disable swap permanently
      ansible.builtin.command: swapoff -a
      changed_when: false

    - name: Remove swap entry from fstab
      ansible.builtin.lineinfile:
        path: /etc/fstab
        regexp: '^\S+\s+\S+\s+swap\s+'
        state: absent

    - name: Load required kernel modules
      community.general.modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - br_netfilter
        - ip_vs
        - nf_conntrack

    - name: Configure sysctl for Kubernetes networking
      ansible.posix.sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        sysctl_file: /etc/sysctl.d/k3s.conf
        reload: true
      loop:
        - { key: "net.bridge.bridge-nf-call-iptables", value: "1" }
        - { key: "net.bridge.bridge-nf-call-ip6tables", value: "1" }
        - { key: "net.ipv4.ip_forward", value: "1" }

    # ── K3s agent configuration ───────────────────────────────────
    - name: Create K3s config directory
      ansible.builtin.file:
        path: /etc/rancher/k3s
        state: directory
        mode: '0755'

    - name: Deploy K3s agent configuration
      ansible.builtin.template:
        src: k3s-agent-config.yaml.j2
        dest: /etc/rancher/k3s/config.yaml
        mode: '0600'

    # ── K3s agent installation ────────────────────────────────────
    - name: Download and install K3s agent
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION={{ k3s_version }} sh -s - agent
      args:
        creates: /usr/local/bin/k3s
      environment:
        INSTALL_K3S_SKIP_START: "true"

    - name: Start K3s agent service
      ansible.builtin.systemd:
        name: k3s-agent
        state: started
        enabled: true

    - name: Wait for agent to register with cluster
      ansible.builtin.pause:
        seconds: 15
  tags:
    - k3s-agents
```

Create `ansible/playbooks/templates/k3s-agent-config.yaml.j2`:

```yaml
# {{ ansible_managed }}
# K3s Agent Configuration — Asgard Cluster
server: https://{{ k3s_first_server_ip }}:6443
token: {{ k3s_token }}
node-name: {{ inventory_hostname }}
node-ip: {{ ansible_host }}
```

**Why agents need `server` but servers don't (with external DB):**
- **Servers** discover each other through the shared PostgreSQL datastore
- **Agents** don't talk to PostgreSQL — they join via a server's API endpoint on port 6443

**Docs:**
- [K3s agent CLI reference](https://docs.k3s.io/cli/agent)
- [K3s agent configuration file](https://docs.k3s.io/installation/configuration#configuration-file)

---

## Step 5: Create a site playbook

**What you're doing:** Combining the server and agent playbooks into a single entry point.

Create `ansible/playbooks/k3s-cluster.yml`:

```yaml
---
# K3s Cluster Deployment — Asgard
# Usage: ansible-playbook -i inventory/k3s-cluster.yml playbooks/k3s-cluster.yml --ask-vault-pass

- name: Deploy K3s server nodes
  ansible.builtin.import_playbook: k3s-servers.yml

- name: Deploy K3s agent nodes
  ansible.builtin.import_playbook: k3s-agents.yml
```

**Run it:**

```bash
cd ansible
ansible-playbook -i inventory/k3s-cluster.yml playbooks/k3s-cluster.yml --ask-vault-pass
```

Or with a vault password file:

```bash
ansible-playbook -i inventory/k3s-cluster.yml playbooks/k3s-cluster.yml --vault-password-file ~/.vault_pass
```

**Docs:**
- [Importing playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_includes.html)

---

## Step 6: Verify the cluster

**What you're doing:** Confirming all nodes joined successfully and the cluster is healthy.

### From any server node

```bash
# SSH into the first server
ssh <username>@10.0.0.50

# Check all nodes are Ready
kubectl get nodes -o wide

# Expected output (10 nodes total):
# NAME                             STATUS   ROLES                  AGE   VERSION
# homelab-server-node-02    Ready    control-plane,master   10m   v1.31.4+k3s1
# homelab-server-node-03  Ready    control-plane,master   10m   v1.31.4+k3s1
# ... (3 more servers)
# homelab-agent-node-02    Ready    <none>                 5m    v1.31.4+k3s1
# ... (4 more agents)

# Check system pods
kubectl get pods -n kube-system

# Check cluster info
kubectl cluster-info
```

### Retrieve kubeconfig for local access

```bash
# Copy kubeconfig from first server to your workstation
scp <username>@10.0.0.50:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config

# Edit the server URL to point to the server's real IP (not 127.0.0.1)
sed -i 's/127.0.0.1/10.0.0.50/g' ~/.kube/k3s-config

# Use it
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

**Docs:**
- [K3s cluster access](https://docs.k3s.io/cluster-access)

---

## Gotchas and troubleshooting

### 1. All servers use the same token

The `--token` flag serves two purposes:
1. Cluster membership authentication
2. PBKDF2 passphrase to encrypt bootstrap data stored in PostgreSQL

If servers use different tokens, they cannot read each other's bootstrap data and the cluster
will not form.

**Docs:** [K3s server CLI — token](https://docs.k3s.io/cli/server#cluster-options)

### 2. Do NOT use `--cluster-init` with PostgreSQL

`--cluster-init` bootstraps embedded etcd. It is incompatible with `--datastore-endpoint`.
When using PostgreSQL, all servers simply connect to the same datastore and the first one to
start creates the initial cluster state.

**Docs:** [K3s embedded etcd vs external DB](https://docs.k3s.io/datastore)

### 3. PostgreSQL must be reachable before K3s starts

If the PostgreSQL VM isn't running when K3s servers start, they will fail to bootstrap. Ensure
the database is provisioned first (it has its own cloud-init in the Terraform module).

### 4. Server play should run before agent play

Agents need at least one healthy server to join. The site playbook imports servers first,
then agents, ensuring correct ordering.

### 5. Ansible `serial` for rolling updates

For day-2 operations (upgrades, config changes), consider running with `serial: 1` to avoid
taking all control plane nodes down simultaneously:

```yaml
- name: Rolling K3s server upgrade
  hosts: k3s_servers
  serial: 1
  # ...
```

**Docs:** [Ansible serial](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html#setting-the-batch-size-with-serial)

### 6. K3s version pinning

Always pin `INSTALL_K3S_VERSION` to a specific version. The `get.k3s.io` script installs the
latest stable by default, which can cause version skew between nodes if run at different times.

Check available versions: https://github.com/k3s-io/k3s/releases

---

## What's next

After the cluster is running:

1. **Bootstrap FluxCD** for GitOps — see [FluxCD Bootstrap](./fluxcd-bootstrap.md)
2. **Deploy cert-manager** for automated TLS certificates
3. **Deploy ingress-nginx** for HTTP/HTTPS ingress
4. **Configure SOPS + age** for encrypted secrets in Git
