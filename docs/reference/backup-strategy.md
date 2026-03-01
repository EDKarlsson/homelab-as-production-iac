---
title: Backup Strategy
description: Two-tier PostgreSQL backup strategy with K8s CronJob (Tier 1) and VM-level Ansible-deployed backups (Tier 2) for defense-in-depth
published: true
date: 2026-02-18
tags:
  - backup
  - postgresql
  - cronjob
  - ansible
  - nfs
  - high-availability
---

Two-tier PostgreSQL backup strategy providing defense-in-depth for 8 databases across the HA cluster. Tier 1 runs inside Kubernetes; Tier 2 runs directly on the PostgreSQL VMs.

## Architecture Overview

```
                        PostgreSQL HA Cluster
                        VIP: 10.0.0.44
                              |
         +--------------------+--------------------+
         |                                         |
   Tier 1: K8s CronJob                     Tier 2: VM Cron (Ansible)
   pg_dumpall (all DBs)                    pg_dump (per-database)
   NFS PVC (nfs-kubernetes SC)             Local disk + Synology NAS
   Schedule: 2:00 AM daily                 Schedule: every 6 hours
   Retention: 14 days                      Local: 7 days, NAS: 30 days
   Alerting: Prometheus rules              Status: JSON file + log
```

## Why Two Tiers?

| Concern | Tier 1 (K8s CronJob) | Tier 2 (VM Cron) |
|---------|----------------------|-------------------|
| **Survives K8s outage** | No -- depends on K8s scheduler | Yes -- runs on VM cron, independent of K8s |
| **Survives PG failover** | Yes -- connects via VIP | Yes -- VIP guard pattern, auto-follows primary |
| **Selective restore** | No -- `pg_dumpall` produces single file | Yes -- per-database `pg_dump` files |
| **Full cluster restore** | Yes -- `pg_dumpall` includes roles and tablespaces | No -- per-database only, roles not captured |
| **Off-site copy** | No -- NFS PVC only | Yes -- copies to Synology NAS |
| **Monitoring** | Prometheus alerts (`PGBackupJobFailed`, `PGBackupMissing`) | Log file + JSON status file |
| **Deployment** | Flux GitOps (declarative) | Ansible playbook (imperative) |

The two tiers complement each other: Tier 1 provides full-cluster restorability with Prometheus alerting; Tier 2 provides selective per-database restore, NAS offloading, and independence from the Kubernetes control plane.

## Tier 1: K8s CronJob (pg_dumpall)

The primary backup path runs as a Kubernetes CronJob in the `monitoring` namespace.

### Configuration

| Parameter | Value |
|-----------|-------|
| Schedule | `0 10 * * *` (2:00 AM Pacific = 10:00 UTC) |
| Image | `postgres:16-alpine` |
| Method | `pg_dumpall --clean --if-exists` piped through `gzip` |
| Storage | NFS PVC (`pg-backups`, StorageClass `nfs-kubernetes`) |
| Retention | 14 days (pruned after each run via `find -mtime +14 -delete`) |
| Timeout | 600 seconds (`activeDeadlineSeconds`) |
| Retries | 2 (`backoffLimit`) |
| Concurrency | Forbid (only one job at a time) |

### Credentials

Credentials are stored in 1Password and synced via ExternalSecret:

- **1Password item:** `pg-backup` (Homelab vault)
- **ExternalSecret:** `pg-backup-credentials` in `monitoring` namespace
- **Secret keys:** `pg-host` (VIP 10.0.0.44), `pg-user`, `pgpass` (`.pgpass` format)

### Prometheus Alerting

Two alert rules fire when backups fail:

| Alert | Condition | Severity |
|-------|-----------|----------|
| `PGBackupJobFailed` | CronJob has failed jobs in the last 24 hours | warning |
| `PGBackupMissing` | No successful job completion in the last 36 hours | critical |

### Key Files

| File | Purpose |
|------|---------|
| `kubernetes/platform/monitoring/controllers/pg-backup/cronjob.yaml` | CronJob manifest |
| `kubernetes/platform/monitoring/controllers/pg-backup/pvc.yaml` | NFS PersistentVolumeClaim |
| `kubernetes/platform/monitoring/controllers/pg-backup/external-secret.yaml` | Credential sync from 1Password |
| `kubernetes/platform/monitoring/controllers/pg-backup/kustomization.yaml` | Kustomize resource list |

## Tier 2: VM-Level Per-Database Backups

Deployed via Ansible, this tier runs directly on both PostgreSQL HA nodes as a system cron job.

### VIP Guard Pattern

The critical design pattern enabling HA-aware backups: the same cron job and backup script are deployed to BOTH nodes (primary and standby), but the script starts with a VIP guard that checks whether the floating VIP (10.0.0.44) is assigned to the local node. Only the current VIP holder executes the backup. The standby silently exits with code 0.

```bash
# VIP guard: only back up on the current primary
if ! ip addr show | grep -q "${VIP}"; then
    log "Not VIP holder (${VIP} not on this node). Skipping backup."
    exit 0
fi
```

**Why this works for HA:**
- After a failover, the promoted standby acquires the VIP
- On the next cron cycle, the VIP guard passes on the new primary
- The old primary (now demoted or offline) either fails the guard or is not running
- No reconfiguration, no manual intervention, no Ansible re-run needed

### Configuration

Defined in `ansible/inventory/group_vars/pg_nodes.yml`:

| Parameter | Value | Variable |
|-----------|-------|----------|
| Schedule | `0 */6 * * *` (every 6 hours) | `pg_backup_cron_schedule` |
| VIP | 10.0.0.44 | `pg_backup_vip` |
| Local backup dir | `/var/backups/postgresql` | `pg_backup_local_dir` |
| Local retention | 7 days | `pg_backup_local_retention_days` |
| NAS mount point | `/mnt/nas-backups` | `pg_backup_nas_mount` |
| NAS server | 10.0.0.161 (Synology) | `pg_backup_nas_server` |
| NAS export path | `/volume1/postgresql-backups` | `pg_backup_nas_path` |
| NAS retention | 30 days | `pg_backup_nas_retention_days` |

### Databases Backed Up

All 8 application databases:

| Database | Consumer |
|----------|----------|
| `k3s` | K3s datastore |
| `terraform_state` | Terraform remote backend |
| `keycloak` | Keycloak identity provider |
| `n8n` | n8n workflow automation |
| `wikijs` | Wiki.js knowledge base |
| `teamcity` | TeamCity CI/CD |
| `coder` | Coder remote development |
| `windmill` | Windmill workflow automation |

### Backup Flow

1. **VIP guard** -- check if this node holds the VIP; exit 0 if not
2. **Per-database dump** -- `sudo -u postgres pg_dump <db> | gzip` for each database
3. **Local retention** -- prune `.sql.gz` files older than 7 days
4. **NAS sync** -- if NAS is mounted, copy today's dumps to `<NAS>/<hostname>/`
5. **NAS retention** -- prune NAS copies older than 30 days
6. **Status file** -- write JSON with per-database results, NAS sync status, errors

### NFS Mount Setup

The NAS mount is configured with resilient options to prevent boot hangs:

```
10.0.0.161:/volume1/postgresql-backups /mnt/nas-backups nfs defaults,nofail,soft,timeo=30,retrans=3 0 0
```

| Option | Purpose |
|--------|---------|
| `nofail` | Do not fail boot if NFS server is unreachable |
| `soft` | Return errors on timeout instead of hanging indefinitely |
| `timeo=30` | 3-second timeout per NFS RPC attempt (units are deciseconds) |
| `retrans=3` | Retry each RPC 3 times before failing |

**Cloud-init gotcha:** Ubuntu does not have `/etc/fstab.d/`, and cloud-init's `write_files` module does not support append mode. The fstab entry must be added via `runcmd`:

```yaml
runcmd:
  - |
    mkdir -p /mnt/nas-backups
    echo "10.0.0.161:/volume1/postgresql-backups /mnt/nas-backups nfs defaults,nofail,soft,timeo=30,retrans=3 0 0" >> /etc/fstab
    mount -a || true
```

### Status File

Each backup run writes `/var/backups/postgresql/backup-status.json`:

```json
{
  "timestamp": "2026-02-18T10:00:05Z",
  "hostname": "k3s-pg-primary",
  "is_vip_holder": true,
  "databases": {
    "k3s": {"status": "ok", "size_bytes": 524288, "file": "k3s-20260218_100000.sql.gz"},
    "keycloak": {"status": "ok", "size_bytes": 1048576, "file": "keycloak-20260218_100002.sql.gz"}
  },
  "nas_sync": "ok",
  "errors": []
}
```

### Deployment

```bash
# Deploy backup automation to both PG HA nodes
export SSH_AUTH_SOCK=~/.1password/agent.sock
ansible-playbook -i ansible/inventory/k3s.yml ansible/playbooks/pg-backup.yml --forks=1
```

The playbook:
1. Installs `nfs-common` on both nodes
2. Creates the NAS mount point and adds the fstab entry
3. Creates the local backup directory
4. Deploys the backup script from the Jinja2 template
5. Installs the cron entry (`/etc/cron.d/pg-backup`)
6. Installs logrotate config for `/var/log/pg-backup.log`
7. Verifies NAS mount and VIP status
8. Runs an initial backup on the VIP holder

### Key Files

| File | Purpose |
|------|---------|
| `ansible/playbooks/pg-backup.yml` | Deployment playbook |
| `ansible/templates/backup-pg-dbs.sh.j2` | Backup script template |
| `ansible/inventory/group_vars/pg_nodes.yml` | Configuration variables |
| `ansible/inventory/k3s.yml` | Inventory (pg_nodes group) |

## Restore Procedures

### Restore from Tier 1 (pg_dumpall)

Full cluster restore including roles and tablespaces:

```bash
# Find the backup file
kubectl exec -n monitoring <pg-backup-pod> -- ls -lh /backups/postgresql/

# Restore (destructive -- drops and recreates all databases)
gunzip -c /backups/postgresql/<date>.sql.gz | sudo -u postgres psql -h 10.0.0.44
```

### Restore from Tier 2 (per-database pg_dump)

Selective single-database restore:

```bash
# From local backup
gunzip -c /var/backups/postgresql/<db>-<timestamp>.sql.gz | sudo -u postgres psql <db>

# From NAS backup
gunzip -c /mnt/nas-backups/<hostname>/<db>-<timestamp>.sql.gz | sudo -u postgres psql <db>
```

**Note:** Tier 2 backups do not include PostgreSQL roles. If restoring to a fresh cluster, create the database user and roles first:

```bash
sudo -u postgres psql -c "CREATE USER <dbuser> WITH ENCRYPTED PASSWORD '<password>';"
sudo -u postgres psql -c "CREATE DATABASE <db> OWNER <dbuser>;"
```

## Prerequisites

- **Synology NAS:** NFS share `/volume1/postgresql-backups` must exist with read/write access for 10.0.0.45 and 10.0.0.46
- **1Password:** Item `pg-backup` in Homelab vault with `pg-host`, `pg-user`, and `pgpass` fields
- **Ansible:** `community.general` and `ansible.posix` collections installed
- **Network:** Both PG nodes must reach the NAS (10.0.0.161) on NFS port (2049)
