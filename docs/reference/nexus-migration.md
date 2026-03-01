---
title: Nexus OrientDB to H2 Migration
description: Nexus Repository Manager migration from OrientDB to H2 database covering the full upgrade path from 3.64.0 through 3.70.3 to 3.89.1
published: true
date: 2026-02-19
tags:
  - nexus
  - migration
  - database
  - kubernetes
  - helm
---

Nexus Repository Manager migration from OrientDB to H2 database. Covers the full upgrade path from version 3.64.0 through the migration checkpoint at 3.70.3 to the final target version 3.89.1.

## Migration Path

```
3.64.0 --> 3.70.3 (checkpoint) --> OrientDB-to-H2 offline migration --> 3.89.1
```

- **3.70.3** is the last OrientDB-compatible version that includes the migration tooling
- **3.71.0+** requires H2 and will not start on OrientDB
- **3.89.1** ships with Java 21 (not Java 17 as some documentation suggests)

## Chart and Image Strategy

The `nexus-repository-manager` Helm chart version 64.x is deprecated (last release: 64.2.0). To advance the Nexus application version on the deprecated chart, use an `image.tag` override in the HelmRelease values rather than waiting for a chart update.

```yaml
spec:
  values:
    image:
      tag: 3.70.3  # Override for migration checkpoint
```

## Migration Procedure

### Phase A: Prepare and Backup

1. Create a database backup via the Nexus UI: Admin > System > Tasks > "Export databases for backup" > set target path to `/nexus-data/backup/`
2. Upgrade to 3.70.3 by setting the image tag override in the HelmRelease
3. Increase JVM heap to 2G to provide migration headroom:

   ```yaml
   env:
     - name: INSTALL4J_ADD_VM_PARAMS
       value: "-Xms1200M -Xmx2G ..."
   ```

### Phase B: Offline Migration

4. Scale down the Nexus deployment:

   ```bash
   kubectl scale deploy -n nexus --replicas=0
   ```

5. Create a migration pod that mounts the same PVC (the Nexus data volume). The pod needs a JDK and network access to download the migrator JAR.

6. Download the migrator JAR. The version must match the Nexus version exactly:

   ```bash
   curl -LO https://download.sonatype.com/nexus/nxrm3-migrator/nexus-db-migrator-3.70.3-01.jar
   ```

7. Run the migrator FROM the backup directory (it looks for `.bak` files in the current working directory):

   ```bash
   cd /nexus-data/backup
   echo "y" | java -Xmx4G -XX:+UseG1GC -XX:MaxDirectMemorySize=28672M \
     -jar /tmp/nexus-db-migrator-3.70.3-01.jar --migration_type=h2
   ```

8. Copy the resulting database file from the backup directory to the expected location:

   ```bash
   cp /nexus-data/backup/nexus.mv.db /nexus-data/db/
   ```

9. Enable the H2 datastore in Nexus properties:

   ```bash
   echo "nexus.datastore.enabled=true" >> /nexus-data/etc/nexus.properties
   ```

### Phase C: Post-Migration Upgrade

10. Delete the migration pod, then scale Nexus back up:

    ```bash
    kubectl scale deploy -n nexus --replicas=1
    ```

11. Verify Nexus starts successfully on H2, then upgrade to the final target version (3.89.1) by updating the image tag override.

12. Restore normal JVM parameters (remove the 2G migration headroom if not needed at steady state).

13. After reaching 3.85.0+, run a manual "Rebuild Repository Search" task via Admin > System > Tasks.

## Gotchas

| Gotcha | Detail |
|--------|--------|
| Migrator JAR prompts for confirmation | Pipe `echo "y" \|` when running non-interactively in a pod |
| Migrator looks for `.bak` files in CWD | Must `cd` to the backup directory before running the JAR |
| `nexus.datastore.enabled=true` required | Must be set in `/nexus-data/etc/nexus.properties` BEFORE starting Nexus post-migration; without it, Nexus attempts to use OrientDB and fails |
| Migration output location | The migrator creates `nexus.mv.db` in the backup directory, not in `/nexus-data/db/`; it must be moved manually |
| No rollback path | The only recovery option after migration is restoring from the Phase A backup and reverting to the 3.64.0 image |
| Rebuild tasks auto-created but search may be stale | After migration, Nexus auto-creates rebuild tasks, but a manual "Rebuild Repository Search" is recommended on versions 3.85.0+ |
| Migration speed is data-dependent | A small homelab instance (39 records) completes in seconds; production instances with large blob stores can take hours |

## Nexus Monitoring

Nexus exposes Prometheus metrics at `/service/metrics/prometheus`. To scrape these via kube-prometheus-stack:

**ServiceMonitor (`kubernetes/apps/nexus/servicemonitor.yaml`):**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nexus
  namespace: nexus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: nexus-repository-manager
  endpoints:
    - port: nexus-ui
      path: /service/metrics/prometheus
```

**kube-prometheus-stack configuration:**

By default, kube-prometheus-stack only discovers ServiceMonitors in its own namespace or namespaces matching a label selector. To enable cross-namespace ServiceMonitor discovery (e.g., `nexus` namespace), add the following to the kube-prometheus-stack HelmRelease values:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorNamespaceSelector: {}  # Empty = match all namespaces
```

Without this, Prometheus will not scrape ServiceMonitors created in application namespaces outside the monitoring namespace.

**Grafana Dashboard:**

The Nexus dashboard (`kubernetes/platform/monitoring/configs/dashboards/nexus.json`) displays:
- JVM heap and thread metrics
- HTTP request rates and error rates
- Connection pool stats
- Repository blob store usage

## Proxy Repository Setup

After upgrading Nexus, configure it as a caching proxy for upstream registries to reduce external traffic and enable air-gap resilience.

### Helm Proxy Repositories

20 Helm chart proxy repositories are managed via `scripts/nexus/configure-proxy-repos.sh` (idempotent -- safe to re-run):

```bash
bash scripts/nexus/configure-proxy-repos.sh
```

All `HelmRepository` manifests in `kubernetes/` point to Nexus internal URLs:

```
http://nexus-nexus-repository-manager.nexus.svc.cluster.local:8081/repository/<repo-name>/
```

**Critical ordering:** Nexus proxy repos must exist BEFORE the HelmRepository manifests are merged to `main`. Flux applies manifests immediately on push -- if the proxy repos don't exist yet, source-controller gets 404s and cascade-fails all dependent Kustomizations via the health-check dependency chain.

### Docker Registry Proxy Repositories

Three Docker proxy repos provide caching for container images:

| Repository | Upstream |
|------------|---------|
| `docker-hub` | `https://registry-1.docker.io` |
| `docker-ghcr` | `https://ghcr.io` |
| `docker-quay` | `https://quay.io` |

### APT Package Proxy Repositories

Two APT proxy repos for Debian/Ubuntu packages:

| Repository | Upstream |
|------------|---------|
| `apt-ubuntu` | `http://archive.ubuntu.com/ubuntu` |
| `apt-ubuntu-security` | `http://security.ubuntu.com/ubuntu` |

### Containerd Registry Mirrors (K3s Nodes)

K3s nodes are configured to use Nexus as a pull-through cache for container images via the `k3s-registry-mirrors` Ansible playbook:

```bash
uv run ansible-playbook -i ansible/inventory/k3s.yml \
  ansible/playbooks/k3s-registry-mirrors.yml --forks=1
```

Configuration in `ansible/inventory/group_vars/k3s_cluster.yml`:

```yaml
nexus_registry_mirror_url: "10.0.0.202:8081"  # host:port, no scheme
```

The playbook template (`ansible/templates/k3s-registries.yaml.j2`) adds the `http://` scheme, the `/repository/<name>/` path prefix, AND the `/v2` suffix when rendering `/etc/rancher/k3s/registries.yaml` on each node. The resulting endpoint URLs look like:

```yaml
mirrors:
  docker.io:
    endpoint:
      - "http://10.0.0.202:8081/repository/docker-hub/v2"
```

**Why `/v2` must be appended:** containerd detects that the endpoint URL contains a path component (anything after `host:port`) and generates `override_path = true` in its internal configuration. With `override_path = true`, containerd appends the image path directly to the endpoint URL WITHOUT inserting the `/v2/` Docker Registry API prefix. Without the `/v2` suffix in the endpoint, the request hits Nexus at `/repository/docker-hub/sha256:...` which is not a valid Docker API path, and Nexus returns `400 Not a docker request`.

### Dedicated MetalLB IP for Apt Proxy Access

The standard Nexus ingress (via ingress-nginx) is not suitable for use as an apt package mirror from VMs or cloud-init because:

1. ingress-nginx routes all traffic through OAuth2 Proxy
2. `apt` clients do not support OAuth2 authentication flows
3. cloud-init runs before K8s networking is reachable

A dedicated `LoadBalancer` Service exposes Nexus port 8081 directly on the LAN:

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
  loadBalancerClass: metallb.universe.tf
  selector:
    app.kubernetes.io/name: nexus-repository-manager
  ports:
    - port: 8081
      targetPort: 8081
```

**IP allocation:** 10.0.0.202 (one above the ingress-nginx MetalLB IP at 10.0.0.201).

**APT source configuration for VMs:**

```
deb http://10.0.0.202:8081/repository/apt-ubuntu/ noble main restricted universe multiverse
```

This URL bypasses OAuth2 and routes directly to the Nexus repository. Set via `nexus_apt_mirror_url` variable in the Terraform k3s module or cloud-init templates (opt-in -- empty string disables).

## Worktree Workflow for Multi-Phase Upgrades

For upgrades that require intermediate Flux reconciliations (merging config changes to `main` between phases), a Git worktree avoids polluting the primary checkout:

```bash
# Create a worktree for the upgrade
git worktree add /tmp/homelab-iac-nexus-upgrade -b feat/nexus-upgrade

# Make changes in the worktree, commit, push, merge to main
# Flux reconciles the intermediate state from main

# Continue to next phase in the worktree
# Repeat until all phases complete

# Clean up
git worktree remove /tmp/homelab-iac-nexus-upgrade
```

This pattern keeps the primary repo checkout on `main` (the Flux source of truth) while allowing feature branch work in parallel.
