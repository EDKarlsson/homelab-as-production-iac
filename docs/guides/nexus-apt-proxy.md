---
title: Nexus APT Proxy Setup
description: Configuring Sonatype Nexus as an apt mirror for K3s VMs (PVE hosts deferred)
tags: [nexus, apt, package-management, ansible, terraform]
---

# Nexus APT Proxy Setup

Nexus Repository Manager acts as a caching proxy for Ubuntu apt packages. K3s VMs pull packages from Nexus instead of `archive.ubuntu.com` directly, reducing internet traffic and improving reproducibility.

> **Scope:** Only K3s VMs (Ubuntu 24.04) are configured today. Proxmox hosts run Debian bookworm and are deferred — see the [Proxmox Hosts](#proxmox-hosts-not-yet-configured) section.

## Architecture

```
K3s VM / PVE host
  └─ apt sources → http://10.0.0.202:8081/repository/apt-ubuntu/
                        └─ Nexus proxy repo (caches on demand)
                              └─ upstream: http://archive.ubuntu.com/ubuntu
```

Nexus runs in K8s, exposed on LAN via a dedicated MetalLB LoadBalancer IP (`10.0.0.202`). This IP is reachable:
- During cloud-init on new VMs (before K8s/Tailscale networking exists)
- From Proxmox hosts (not cluster members)
- Without OAuth2 authentication (Nexus anonymous access is enabled)

The ingress-nginx VIP (`10.0.0.201`) is **not used** here — that goes through OAuth2 Proxy which blocks unauthenticated apt clients.

## Nexus Repos Involved

| Nexus repo | Proxies upstream |
|---|---|
| `apt-ubuntu` | `http://archive.ubuntu.com/ubuntu` |
| `apt-ubuntu-security` | `http://security.ubuntu.com/ubuntu` |

Both are proxy repos configured in Nexus at install time. Packages are cached on first request.

## Components

### 1. K8s LoadBalancer Service

**File**: `kubernetes/apps/nexus/service-lb.yaml`

A separate Service (type `LoadBalancer`) alongside the Helm chart's ClusterIP service. MetalLB allocates `10.0.0.202` via the `metallb.universe.tf/loadBalancerIPs` annotation.

```yaml
# kubernetes/apps/nexus/service-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: nexus-lb
  namespace: nexus
  annotations:
    metallb.universe.tf/loadBalancerIPs: 10.0.0.202
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: nexus-repository-manager
    app.kubernetes.io/instance: nexus
  ports:
    - name: http
      port: 8081
      targetPort: 8081
      protocol: TCP
```

### 2. Terraform Variable (future VMs)

**File**: `infrastructure/main.tf`, `module "k3s"` block

```hcl
module "k3s" {
  # ... existing args ...
  nexus_apt_mirror_url = "http://10.0.0.202:8081"
}
```

The cloud-init templates (`k3s-server.yml.tftpl`, `k3s-agent.yml.tftpl`) already have a conditional block that writes the apt sources when this variable is non-empty. **This only affects new VMs** — cloud-init runs once at first boot.

### 3. Ansible Playbook (existing VMs)

**File**: `ansible/playbooks/nexus-apt-mirror.yml`

Since cloud-init already ran on existing VMs, Ansible configures apt sources in-place.

**What it does**:
1. Writes `/etc/apt/sources.list.d/nexus-ubuntu.sources` in deb822 format
2. Renames `/etc/apt/sources.list.d/ubuntu.sources` → `ubuntu.sources.disabled` (reversible)
3. Runs `apt-get update` to verify connectivity

**Run it**:
```bash
ansible-playbook -i ansible/inventory/k3s.yml \
  ansible/playbooks/nexus-apt-mirror.yml \
  -e nexus_apt_url=http://10.0.0.202:8081 \
  --forks=1
```

To revert (re-enable upstream sources):
```bash
ansible -i ansible/inventory/k3s.yml k3s_cluster -b -m command \
  -a "mv /etc/apt/sources.list.d/ubuntu.sources.disabled /etc/apt/sources.list.d/ubuntu.sources" \
  --forks=1
ansible -i ansible/inventory/k3s.yml k3s_cluster -b -m file \
  -a "path=/etc/apt/sources.list.d/nexus-ubuntu.sources state=absent" \
  --forks=1
```

## Proxmox Hosts (Not Yet Configured)

PVE hosts run **Debian bookworm**, not Ubuntu. The current Nexus deployment only has `apt-ubuntu` and `apt-ubuntu-security` proxy repos.

To configure PVE hosts, you would need to:

1. Add Debian proxy repos to Nexus:
   - `apt-debian` → `https://deb.debian.org/debian`
   - `apt-debian-security` → `https://security.debian.org/debian-security`
   - `apt-proxmox` → `http://download.proxmox.com/debian` (Proxmox-specific packages)

2. Add PVE hosts to Ansible inventory (`pve_hosts` group — doesn't exist yet)

3. Add tasks to the `Configure Nexus APT mirror on Proxmox hosts` play in the playbook

## IP Address Allocation

| IP | Service |
|---|---|
| `10.0.0.201` | ingress-nginx (MetalLB) |
| `10.0.0.202` | nexus-lb (MetalLB) — apt proxy |
| `10.0.0.203+` | available |

## Troubleshooting

**`apt update` fails with connection refused**
- Check that the LoadBalancer service got its IP: `kubectl get svc -n nexus nexus-lb`
- Confirm MetalLB assigned it: `kubectl get ipaddresspool -n metallb-system`

**`apt update` fails with 404**
- The Nexus proxy repo may not be online. Check: `curl -s http://10.0.0.202:8081/repository/apt-ubuntu/dists/noble/InRelease | head -5`
- Verify Nexus is healthy: `kubectl get pods -n nexus`

**Packages are slow on first install**
- Expected — Nexus fetches from upstream and caches on first request. Subsequent installs are fast.

**Reverting to upstream apt**
- See revert commands in the Ansible section above. The `.disabled` rename makes it safe to undo.
