---
title: Longhorn Distributed Block Storage
description: Longhorn deployment pattern for the K3s homelab cluster with replicated block storage across nodes
published: true
date: 2026-02-18
tags:
  - longhorn
  - storage
  - kubernetes
  - helm
  - cncf
---

Longhorn deployment pattern for the K3s homelab cluster. Longhorn is a CNCF-graduated lightweight distributed block storage system for Kubernetes.

## Overview

Longhorn provides replicated block storage across K3s nodes, complementing the existing NFS provisioner (for shared read-write-many workloads) and local-path provisioner (for node-pinned workloads).

**Use cases by StorageClass:**

| StorageClass | Provider | Access Modes | Best For |
|-------------|----------|-------------|----------|
| `nfs-kubernetes` | NFS provisioner | RWX, RWO | Shared data, media, backups |
| `local-path` | K3s built-in | RWO (node-pinned) | Databases requiring local disk (YouTrack Xodus) |
| `longhorn` | Longhorn | RWO, RWX (via NFS) | Replicated block storage, stateful apps needing HA |

## Node Prerequisites

All K3s nodes (servers and agents) require these packages for Longhorn's iSCSI and NFS support:

```bash
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
```

These should be included in the cloud-init `packages:` list for new nodes, or applied via Ansible for existing nodes.

**Verification:**

```bash
# Check on all nodes
scripts/k8s/k3s-ssh.sh all 'systemctl is-active iscsid && dpkg -l | grep nfs-common'
```

## Helm Chart Configuration

Deployed as a platform controller via Flux HelmRelease at `kubernetes/platform/controllers/longhorn.yaml`.

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 1h
  install:
    remediation:
      retries: 3
  chart:
    spec:
      chart: longhorn
      version: "1.x"
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: longhorn-system
      interval: 12h
  values:
    defaultSettings:
      defaultReplicaCount: 2
      defaultDataLocality: best-effort
      storageMinimalAvailablePercentage: 15
      defaultLonghornStaticStorageClass: longhorn
    persistence:
      defaultClassReplicaCount: 2
      defaultClass: false
    ingress:
      enabled: false
```

### Key Configuration Decisions

| Setting | Value | Rationale |
|---------|-------|-----------|
| `defaultReplicaCount: 2` | 2 replicas | Balance between redundancy and disk usage on a 5-agent cluster; 3 replicas would consume 60% more storage |
| `defaultDataLocality: best-effort` | best-effort | Tries to schedule a replica on the same node as the consuming pod for lower latency |
| `storageMinimalAvailablePercentage: 15` | 15% | Prevents Longhorn from filling disks beyond 85% capacity |
| `defaultClass: false` | false | Does NOT set Longhorn as the cluster default StorageClass; avoids overriding the existing `local-path` default |
| `ingress.enabled: false` | false | No Longhorn UI exposed; manage via kubectl or Portainer |

### Why `defaultClass: false`

K3s ships with `local-path` as the default StorageClass. Setting `defaultClass: true` on Longhorn would make it the implicit storage for any PVC that omits `storageClassName`. This is undesirable because:

1. Longhorn has higher overhead than local-path (replication, iSCSI target management)
2. Some workloads intentionally use local-path for node-pinned storage (e.g., YouTrack Xodus DB)
3. Explicit `storageClassName: longhorn` in PVCs makes storage selection intentional and auditable

## Reconciliation Order

Longhorn is listed in `kubernetes/platform/controllers/kustomization.yaml` and reconciles as part of `platform-controllers`. The `wait: true` setting on the platform-controllers Kustomization ensures Longhorn's StorageClass is available before any app PVCs that reference it.

```
platform-controllers (wait: true)
    |-- longhorn.yaml  -->  Creates: Namespace, HelmRepository, HelmRelease
    |                       Produces: StorageClass "longhorn", CSI driver
    |
platform-configs (dependsOn: platform-controllers)
    |
apps (dependsOn: platform-configs)
    |-- <app> with storageClassName: longhorn  -->  PVC binds successfully
```

## Operational Notes

- **Dashboard:** Longhorn UI is not exposed via ingress. Access via `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80` if needed.
- **Disk space:** Each Longhorn node uses local disk (local-lvm in Proxmox). Monitor via Grafana or `kubectl -n longhorn-system get nodes.longhorn.io`.
- **Backup:** Longhorn supports S3-compatible backup targets. Not yet configured for this cluster.

## Key Files

| File | Purpose |
|------|---------|
| `kubernetes/platform/controllers/longhorn.yaml` | Namespace + HelmRepository + HelmRelease |
| `kubernetes/platform/controllers/kustomization.yaml` | Includes longhorn.yaml in platform controllers |
