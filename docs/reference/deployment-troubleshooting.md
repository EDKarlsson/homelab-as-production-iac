---
title: Deployment Troubleshooting
description: Issues encountered during K3s cluster deployment with root cause analysis and resolutions
published: true
date: 2026-02-21
tags:
  - troubleshooting
  - k3s
  - terraform
  - deployment
  - cloud-init
  - keepalived
---

Issues encountered during K3s cluster deployment with root cause analysis and resolutions. Each entry follows the pattern: Symptom, Root Cause, Resolution.

## SSH Authentication Failure (Terraform Provider)

**Symptom:** `terraform apply` fails immediately with:

```
attempted methods [none password], no supported methods remain
```

The bpg/proxmox provider cannot authenticate as `root` over SSH to Proxmox nodes.

**Root Cause:** The default `SSH_AUTH_SOCK` on the workstation points to GNOME Keyring's agent (`/run/user/1000/keyring/ssh`). Go's `golang.org/x/crypto/ssh/agent` library (used by the bpg/proxmox provider) is incompatible with GNOME Keyring's SSH agent protocol implementation. Even though `ssh-add -L` shows keys and manual `ssh root@<node>` works, the Go library cannot negotiate with GNOME Keyring.

GNOME Keyring implements a subset of the SSH agent protocol and has known incompatibilities with non-OpenSSH clients. The Go SSH library sends agent requests that GNOME Keyring does not understand, causing the authentication handshake to fail.

**Resolution:** Add a 1Password data source for the PVE root SSH key and pass the private key directly to the provider, bypassing the SSH agent entirely:

```hcl
data "onepassword_item" "pve_root" {
  vault = data.onepassword_vault.homelab.uuid
  title = "ssh-homelab-pve-root-2025"
}

provider "proxmox" {
  ssh {
    agent       = true
    username    = "root"
    private_key = data.onepassword_item.pve_root.private_key
  }
}
```

## Terraform Apply Stuck "Still Creating" (QEMU Guest Agent)

**Symptom:** `terraform apply` creates VMs (visible in Proxmox UI, running), but Terraform reports "still creating" indefinitely for all VMs. They never complete.

**Root Cause:** The VM resource has `agent { enabled = true, timeout = "15m" }` which tells the bpg/proxmox provider to wait for the QEMU guest agent to respond before marking the resource as created. However, `qemu-guest-agent` was not included in any of the cloud-config template package lists, so the agent never starts inside the VMs.

The `agent { enabled = true }` block configures the Proxmox hypervisor to expect a guest agent, and the provider uses the agent's response as a signal that the VM is fully booted. Without the guest agent package installed in the OS, the provider waits until the timeout.

**Resolution:** Add `qemu-guest-agent` to the `packages:` list in all three cloud-config templates (`k3s-server.yml.tftpl`, `k3s-agent.yml.tftpl`, `postgresql.yml.tftpl`).

## VMs Unreachable on Network (VLAN Double-Tagging)

**Symptom:** All 9 VMs created successfully (Terraform apply completes), VMs show assigned IP addresses in Unifi network management, but no VM responds to ping or SSH from the local network.

**Root Cause:** The VM `network_device` blocks included `vlan_id = 2`, but the Proxmox host bridge `vmbr0` is already configured as an untagged/access port on VLAN 2. Adding `vlan_id = 2` to the VM NIC causes the guest to send 802.1Q-tagged frames, which the already-untagged bridge double-tags. The upstream switch either drops or misroutes these frames.

There are two ways to assign a VLAN to a VM in Proxmox:
1. **Bridge-level (access port):** The bridge (`vmbr0`) is connected to an access/untagged port on the physical switch for VLAN 2. VMs inherit VLAN membership automatically -- no `vlan_id` needed.
2. **VM-level (trunk port):** The bridge is connected to a trunk port carrying multiple VLANs. The VM specifies `vlan_id` to tag its traffic.

In this homelab, `vmbr0` is on an access port for VLAN 2 (10.0.0.0/24). Setting `vlan_id = 2` on the VM creates a double-tagged frame that the switch drops.

**Resolution:** Remove `vlan_id` from all `network_device` blocks in `k3s-cluster.tf`. VMs inherit VLAN 2 membership through the untagged bridge.

## Cannot Access VM Console (No Password Set)

**Symptom:** Cannot log into VMs via Proxmox noVNC console. Login prompt appears but no password works.

**Root Cause:** The cloud-config sets `lock_passwd: false` for the user, but never sets an actual password (no `passwd:` field, no `chpasswd:` block). In Ubuntu 24.04, `lock_passwd: false` merely unlocks the account, but PAM still rejects login if no password hash is set.

Cloud-init's `lock_passwd: false` is often confused with "allow passwordless login." It only means "don't lock the password field in /etc/shadow." Without a `passwd:` hash, the password field is empty/invalid, and PAM's `pam_unix.so` rejects authentication.

**Resolution:** For emergency console access, add a `chpasswd:` block to cloud-configs:

```yaml
chpasswd:
  expire: true
  users:
    - name: ${username}
      password: ${console_password}
      type: text
```

This is non-blocking for normal operations (SSH key auth works).

## Incorrect DNS Servers

**Symptom:** DNS resolution fails or uses wrong servers after cloud-init network configuration.

**Root Cause:** The original `initialization` DNS block pointed at `10.0.0.10` and `10.0.0.11`, which are Proxmox node IPs, not DNS servers. No dedicated DNS server runs on the homelab network.

**Resolution:** Change DNS servers to Google DNS (`8.8.8.8`, `8.8.4.4`) in the `k3s_network` local and all `initialization.dns` blocks.

## Terraform Destroy Stuck During Refresh

**Symptom:** `terraform destroy` hangs during the "Refreshing state..." phase with no progress for several minutes.

**Root Cause:** The provider refreshes VM state by querying the QEMU guest agent for network interfaces and other info. When VMs have broken networking, the agent queries time out one by one. With 9 VMs each timing out, the total wait can exceed an hour.

**Resolution:** Use `terraform destroy -refresh=false` to skip the state refresh and proceed directly to destruction. This is safe when VMs exist but are unreachable.

**Caveat:** `-refresh=false` destroys everything in state, including resources outside the target (such as the VM template). Use `-target=module.k3s` to limit the scope of destruction.

## VM Template Destroyed (Collateral from -refresh=false)

**Symptom:** `terraform apply` fails with:

```
Error: error retrieving VM 9000: Configuration file 'nodes/node-02/qemu-server/9000.conf' does not exist
```

**Root Cause:** `terraform destroy -refresh=false` destroyed ALL resources in the state file, including the VM template (VM 9000) which lives in the root module alongside the k3s module resources.

The k3s module VMs reference the template by VM ID (`var.k3s_template_vm_id = 9000`) -- a static number, not a Terraform resource reference. Terraform's dependency graph has no edge from the template to the clones.

**Resolution:** Run `terraform apply` again -- the template is defined in `vm-template.tf` and will be recreated first. For targeted recreation:

```bash
terraform apply -target=proxmox_virtual_environment_download_file.ubuntu_2404_cloud_image \
                -target=proxmox_virtual_environment_vm.ubuntu_2404_cloud_image
# Then:
terraform apply
```

## Cloud-init write_files Owner Error

**Symptom:** Cloud-init reports `status: error` on agent and PostgreSQL VMs:

```
OSError: Unknown user or group: "getpwnam(): name not found: 'k3sadmin'"
```

**Root Cause:** The `write_files` module runs during cloud-init's `init-network` stage (early), but user creation (`users:` directive) happens during the `config` stage (later). Any `write_files` entry with `owner: k3sadmin:k3sadmin` fails because the user does not exist yet.

Cloud-init processes modules in a defined stage order:
1. `init-network` stage -- `write_files`, `bootcmd`, `disk_setup`
2. `config` stage -- `users_groups`, `ssh`, `packages`, `ntp`
3. `final` stage -- `runcmd`, `scripts`, `final_message`

**Impact:** Non-fatal for core functionality. The error only affects alias files in `~/.bashrc.d/`. All critical `runcmd` steps (K3s install, PostgreSQL setup, kernel modules, sysctl) still execute.

**Resolution:** Add `defer: true` to `write_files` entries that reference custom users:

```yaml
write_files:
  - path: /home/${username}/.bashrc.d/k3s-aliases
    defer: true  # Defers to final stage (after user creation)
    owner: ${username}:${username}
    content: |
      ...
```

`defer: true` moves the file write from `init-network` to the `final` stage. Available since cloud-init 21.3 (Ubuntu 24.04 ships with 24.x).

## K3s Server Token Format Invalid

**Symptom:** K3s server service enters crash loop with:

```
level=fatal msg="starting kubernetes: preparing server: failed to normalize server token; must be in format K10<CA-HASH>::<USERNAME>:<PASSWORD> or <PASSWORD>"
```

PostgreSQL connection succeeds (tables created), but token validation fails.

**Root Cause:** The token is in format `K10<hash>::fx954u.gilr93estsa067vz`. The `K10` prefix tells K3s to parse it as a full token with format `K10<CA-HASH>::<USERNAME>:<PASSWORD>`. But the part after `::` is `fx954u.gilr93estsa067vz` (a kubeadm-style `<id>.<secret>` with no colon), which does not match the expected `<username>:<password>` format.

K3s supports two token formats:
1. **Simple:** Any plain string (e.g., `my-cluster-secret`) -- used for initial bootstrap
2. **Full:** `K10<CA-HASH>::<username>:<password>` -- auto-generated by K3s after first server bootstraps

For initial cluster bootstrap with an external PostgreSQL datastore, a **simple token** (plain shared secret) is the correct choice. The `K10` format is for joining nodes to an already-bootstrapped cluster.

**Resolution:** Update the 1Password item to contain a simple shared secret string:
- Must NOT start with `K10`
- Should be a strong random string (e.g., 32+ alphanumeric characters)
- Example: `openssl rand -hex 32`

After the first server bootstraps, K3s auto-generates the full `K10...` token, retrievable via `sudo cat /var/lib/rancher/k3s/server/token`.

## ESO CRD "Already Exists" Conflict

**Symptom:** ESO HelmRelease stuck in `InstallFailed`:

```
customresourcedefinitions.apiextensions.k8s.io "clustersecretstores.external-secrets.io" already exists
```

**Root Cause:** ESO chart ships CRDs via Helm **templates** (controlled by `installCRDs: true` value), NOT the `crds/` directory. On a failed install attempt, orphaned CRDs remained in the cluster. On retry, Helm tried to create them again.

**Wrong fix:** Setting `installCRDs: false` disables ALL CRD installation, causing ESO controller to crash with `no matches for kind "ExternalSecret"`.

**Resolution:** Set `install.crds: Skip` + `upgrade.crds: Skip` in the Flux HelmRelease (no-op since `crds/` dir is empty). Remove `installCRDs: false` to let the chart default handle CRDs. Delete orphaned CRDs and Helm release secrets for a clean retry.

## ClusterSecretStore DNS Resolution Failure

**Symptom:** ClusterSecretStore shows `InvalidProviderConfig`:

```
dial tcp: lookup op-connect.homelab.ts.net on 10.43.0.10:53: no such host
```

**Root Cause:** K8s pods use CoreDNS (10.43.0.10) which cannot resolve Tailscale MagicDNS hostnames (`.ts.net`). Only hosts running the Tailscale daemon can resolve these.

**Resolution:** Change `connectHost` from the Tailscale URL to a LAN IP. Originally pointed at `http://10.0.0.66:8080` (workstation running Connect in Docker). Now uses the HA Connect VIP at `http://10.0.0.72:8080` (keepalived floating IP across two Proxmox LXC containers). The old workstation endpoint (10.0.0.66) has been decommissioned.

## ClusterSecretStore Dev Vault Not Accessible

**Symptom:** ClusterSecretStore shows `InvalidProviderConfig`:

```
Found 0 vaults with title "Dev"
```

**Root Cause:** ESO validates ALL configured vaults on startup. The Connect token only has access to the Homelab vault, not Dev.

**Resolution:** Remove `Dev: 2` from the vaults map. Keep only `Homelab: 1`.

## Loki StatefulSet Immutable Field

**Symptom:** Loki HelmRelease stuck in `UpgradeFailed`:

```
StatefulSet.apps "loki-minio" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template'...
```

**Root Cause:** Pre-existing issue from persistence changes -- `volumeClaimTemplates` on StatefulSets are immutable in Kubernetes.

**Resolution:** Delete Helm release secrets (`sh.helm.release.v1.loki.v1`, `v2`) to force a fresh install, then suspend/resume the HelmRelease.

## K3s /readyz Returns 401 Unauthenticated

**Symptom:** A health check script or monitoring probe reports K3s as "down" because `curl https://<server>:6443/readyz` returns HTTP 401 Unauthorized.

**Root Cause:** The K3s API server's `/readyz` endpoint requires authentication. Unlike `/healthz` on some Kubernetes distributions, K3s does not serve `/readyz` to anonymous clients. An unauthenticated request returns 401 (or 403), which naive health checks interpret as a failure.

**Resolution:** Health check logic must treat HTTP 200, 401, and 403 as "server is reachable and responding." Only connection refused, timeout, or no response indicates the server is actually down. For authenticated checks, pass a bearer token or client certificate:

```bash
# Unauthenticated check (accept 401/403 as healthy):
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://<server>:6443/readyz)
if [[ "$HTTP_CODE" =~ ^(200|401|403)$ ]]; then
  echo "K3s API server is reachable"
fi

# Authenticated check:
curl -sk --cacert /var/lib/rancher/k3s/server/tls/server-ca.crt \
  --cert /var/lib/rancher/k3s/server/tls/client-admin.crt \
  --key /var/lib/rancher/k3s/server/tls/client-admin.key \
  https://<server>:6443/readyz
```

## Flux Bootstrap SSH vs HTTPS URL Mismatch

**Symptom:** After running `flux bootstrap github`, Flux fails to reconcile with authentication errors even though the deploy key or PAT is valid. The `GitRepository` resource shows errors like `ssh: handshake failed` or `authentication required`.

**Root Cause:** `flux bootstrap github` writes an SSH URL (`ssh://git@github.com/...`) into `flux-system/gotk-sync.yaml` by default. If the GitRepository was previously configured with an HTTPS URL (e.g., `https://github.com/<org>/<repo>.git`), the existing secret contains an HTTPS token, not an SSH deploy key. The URL scheme and authentication method are mismatched.

This also happens in reverse: bootstrapping with `--token-auth` (HTTPS) when the existing GitRepository uses an SSH URL and deploy key secret.

**Resolution:** Ensure the GitRepository URL scheme matches the authentication method:

- **SSH bootstrap:** URL is `ssh://git@github.com/<org>/<repo>`, secret contains a deploy key
- **HTTPS bootstrap (`--token-auth`):** URL is `https://github.com/<org>/<repo>`, secret contains a GitHub PAT

If switching between methods, delete the `flux-system` namespace and re-bootstrap cleanly:

```bash
flux uninstall --namespace=flux-system
flux bootstrap github \
  --owner=<org> --repository=<repo> \
  --path=clusters/homelab \
  --personal --token-auth  # for HTTPS, or omit for SSH
```

## NFS Mount Access Denied After VM IP Changes

**Symptom:** After rebuilding the K3s cluster (new VMs with different IPs from DHCP or Terraform), NFS-backed PersistentVolumes fail to mount with `access denied by server` or `mount.nfs: access denied by server while mounting`.

**Root Cause:** The NAS (e.g., Synology) NFS share permissions use an IP-based allowlist. When VMs are destroyed and recreated, they may receive different IP addresses from DHCP. The new IPs are not in the NAS allowlist, so NFS mount requests are rejected.

**Resolution:** Update the NAS NFS share permissions to include the new VM IPs. To avoid this recurring on every rebuild:

- Use a CIDR range (`10.0.0.0/24`) instead of individual IPs in the NAS NFS share allowlist
- Or use static IPs for K3s nodes (configured via cloud-init `ip_config` in Terraform) so IPs survive rebuilds

On Synology DSM: Control Panel -> Shared Folder -> Edit -> NFS Permissions -> update the allowed client IP list or CIDR.

## Helm StatefulSet Immutable Fields from Version Downgrade/Rollback

**Symptom:** After downgrading a Helm chart version and then upgrading back to the original version, the HelmRelease fails with:

```
StatefulSet.apps "<name>" is invalid: spec: Forbidden: updates to statefulset spec
for fields other than 'replicas', 'ordinals', 'template', 'persistentVolumeClaimRetentionPolicy'...
```

This occurs even though the final desired state should match what was previously running.

**Root Cause:** The intermediate downgrade may have changed immutable StatefulSet fields (such as `volumeClaimTemplates`, `serviceName`, or `podManagementPolicy`). Kubernetes records the current spec and rejects any update that modifies immutable fields, regardless of whether the "new" spec matches a previously known-good state. Helm's three-way merge detects a diff between the live state (downgraded) and the desired state (re-upgraded) and attempts an update, which Kubernetes rejects.

**Resolution:** Three approaches, in order of preference:

1. **Flux force upgrade:** Set `spec.upgrade.force: true` on the HelmRelease. Flux will delete the release and recreate it, bypassing the immutable field check.

2. **Delete the StatefulSet (preserve PVCs):** Delete the StatefulSet without cascading to pods/PVCs, then let Helm recreate it:

   ```bash
   kubectl delete statefulset <name> --cascade=orphan -n <namespace>
   # Then trigger reconciliation:
   flux reconcile helmrelease <name> -n <namespace>
   ```

3. **Delete Helm release secrets:** Remove all `sh.helm.release.v1.<name>.v*` secrets in the namespace to force a fresh install:

   ```bash
   kubectl delete secret -n <namespace> -l name=<release>,owner=helm
   flux reconcile helmrelease <name> -n <namespace>
   ```

## Keepalived Interface Name Mismatch (PostgreSQL HA)

**Symptom:** Keepalived fails to start on a VM with:

```
WARNING - interface ens18 for vrrp_instance VI_POSTGRES doesn't exist
Non-existent interface specified in configuration
```

**Root Cause:** The cloud-init template hardcoded `interface ens18` in the keepalived config, but Ubuntu 24.04 cloud images with Proxmox virtio NICs use `eth0`. Predictable interface naming (`ens*`) requires PCI slot metadata that cloud images lack.

**Resolution:** Change `interface ens18` to `interface eth0` in the cloud-init templates and on any running VMs. Always verify the actual interface name with `ip link show` before hardcoding in keepalived config.

**Files Modified:** `modules/pg-ha/cloud-configs/postgresql-{primary,standby}.yml.tftpl`, `/etc/keepalived/keepalived.conf` on both VMs

## Keepalived Health Check Deadlock (PostgreSQL HA)

**Symptom:** Failover test fails -- VIP stays on the dead primary after stopping PostgreSQL. The standby never acquires the VIP.

**Root Cause:** The health check script verified both `pg_isready` AND `pg_is_in_recovery() = 'f'` (confirming the node is primary). The standby always fails this check because it IS in recovery, so keepalived drops its priority by the weight penalty. After failover: primary (100-20=80) still > standby (90-20=70). The VIP stays on the dead node.

**Resolution:** Simplify the health check to only test `pg_isready`. Role detection is handled by keepalived priorities (MASTER/BACKUP) and the notify script (which contains promotion logic). The health check should only answer "is PostgreSQL running?" -- not "is it the primary?"

This creates a deadlock where the standby can never win the VRRP election because checking recovery status in the health check causes both nodes' priorities to drop when the standby is active.

**Files Modified:** `modules/pg-ha/scripts/pg-health-check.sh`, both cloud-init templates, `/usr/local/bin/pg-health-check.sh` on both VMs

## Premature Standby Promotion (PostgreSQL HA)

**Symptom:** After fixing keepalived on the standby and restarting it (before installing keepalived on the primary), the standby auto-promoted to primary. Both nodes became independent primaries (split-brain).

**Root Cause:** Keepalived on the standby started with no VRRP peer responding (the primary did not have keepalived yet). After approximately 3 seconds with no advertisements, the BACKUP transitioned to MASTER. The notify script detected `pg_is_in_recovery() = 't'` and promoted PostgreSQL. When keepalived was later installed on the primary, it reclaimed VIP (higher priority), but PostgreSQL promotion is irreversible.

**Resolution:** Re-initialize the standby via `pg_basebackup` from the primary to restore the replication relationship. Always install keepalived on the MASTER node first, or keep the BACKUP's keepalived stopped until both nodes are ready.

**Lesson:** Keepalived deployment order matters in HA setups. Install/start on MASTER first to prevent premature BACKUP promotion.

## Homepage Widget Debugging Patterns

**Symptom:** Homepage widgets show "Error", "API Error", or blank data despite the service being reachable from a browser.

**Root Cause (varies by widget):** Homepage makes server-side API calls from within the pod. Common failure modes:

1. **Wrong service name in URL:** The `url` field in widget config must use the actual Kubernetes Service name, which often differs from the app name or HelmRelease name. For example, Plex's service is `plex-plex-media-server`, not `plex`; Grafana's service is `kube-prometheus-stack-grafana`, not `grafana`.

2. **Proxmox API token privilege separation:** Proxmox API tokens created under `root@pam` with "Privilege Separation" checked (the default) do NOT inherit root's privileges. The token has zero permissions until explicitly granted a role (e.g., `PVEAuditor`) via Datacenter -> Permissions -> Add -> API Token Permission on path `/`.

3. **Chart version lag (image override):** The jameswynn Homepage Helm chart v2.x bundles app version v1.2.0, but the latest Homepage app is v1.10.1. Many widgets (including Portainer with `kubernetes: true` for K8s environment stats) only work in newer app versions. Override the image tag in HelmRelease values.

4. **Longhorn widget URL placement:** The Longhorn provider URL goes in `settings.providers.longhorn.url` (inside the `settingsString` config block), NOT in the `widgets` section. The widget block only contains display options like `expanded` and `total`.

5. **MagicDNS resolution failure:** Pods cannot resolve `.ts.net` hostnames (CoreDNS uses cluster DNS, not host resolver). Widget URLs must use cluster-internal service names (`http://<svc>.<ns>.svc.cluster.local:<port>`) or LAN IPs, never Tailscale MagicDNS URLs.

**Debugging steps:**

```bash
# 1. Find the actual service name and port
kubectl get svc -n <namespace>

# 2. Check pod logs for API errors
kubectl logs -n homepage deployment/homepage --tail=100 | grep -i error

# 3. Test connectivity from inside the pod
kubectl exec -n homepage deployment/homepage -- wget -qO- http://<svc>.<ns>.svc.cluster.local:<port>/api/health

# 4. Verify ExternalSecret sync (credentials populated?)
kubectl get externalsecret -n homepage
kubectl get secret homepage-widget-secrets -n homepage -o jsonpath='{.data}' | jq 'keys'

# 5. Force ExternalSecret re-sync after updating 1Password item
kubectl annotate externalsecret homepage-widget-secrets -n homepage \
  force-sync="$(date +%s)" --overwrite

# 6. Restart Homepage to pick up new secrets
kubectl rollout restart deployment homepage -n homepage
```

---

## GitHub Actions Exporter Probe Failure (CrashLoopBackOff)

**Symptom:** The `github-actions-exporter` pod enters CrashLoopBackOff immediately after deployment. Liveness probe fails repeatedly:

```
Liveness probe failed: HTTP probe failed with statuscode: 404
```

**Root Cause:** The initial deployment used `httpGet` probes pointing at `/healthz`. The `Labbs/github-actions-exporter` does NOT expose a `/healthz` endpoint -- it only serves the `/metrics` path. Every `httpGet` probe to `/healthz` returns HTTP 404, which kubelet interprets as a probe failure, triggering pod restarts.

**Resolution:** Switch to `tcpSocket` probes on the metrics port (9999):

```yaml
livenessProbe:
  tcpSocket:
    port: metrics
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  tcpSocket:
    port: metrics
  initialDelaySeconds: 5
  periodSeconds: 10
```

**Additional complication:** `kubectl apply` cannot change a probe's handler type in-place. Attempting to change from `httpGet` to `tcpSocket` via `kubectl apply` returns:

```
Invalid value: "": may not specify more than 1 handler type
```

Kubernetes treats the existing `httpGet` and the new `tcpSocket` as two handler types specified simultaneously. The fix is to delete the Deployment first, then recreate it:

```bash
kubectl delete deployment github-actions-exporter -n monitoring
kubectl apply -f kubernetes/platform/monitoring/controllers/github-actions-exporter/deployment.yaml
```

Or with Flux, set `spec.upgrade.force: true` on the HelmRelease/Kustomization to handle the recreation automatically.

**Files Modified:** `kubernetes/platform/monitoring/controllers/github-actions-exporter/deployment.yaml`

## Flux Kustomization Blocked by Single Failing Resource (Atomicity)

**Symptom:** A Flux Kustomization shows `ReconciliationFailed` and no resources in it are being updated, even though only one resource has an issue. Error example:

```
apply failed: ... PersistentVolumeClaim "xyz" is invalid
```

**Root Cause:** Flux Kustomization reconciliation is **atomic**. When Flux runs `kustomize build` and applies the resulting manifests, it performs a server-side dry-run first. If ANY resource in the Kustomization fails validation (dry-run or apply), the ENTIRE Kustomization is blocked. No resources are applied, even those that are perfectly valid.

This means a single broken PVC, invalid label, or schema error prevents all other resources in the same Kustomization (potentially dozens of apps) from reconciling.

**Resolution:** Fix or remove the failing resource. If the fix requires investigation, temporarily remove the broken resource from the Kustomization's `resources:` list to unblock the rest. Common triggers:

1. **Dynamically provisioned PVCs missing `volumeName`:** Once a PVC is bound to a PV, Flux dry-run creates a hypothetical PVC that conflicts with the existing bound one. Add `volumeName: <pv-name>` to the PVC manifest.
2. **PV with immutable field changes:** PV `spec` fields (like `nfs.path`) cannot be changed in-place. Delete PV + PVC and let Flux recreate.
3. **CRD not yet installed:** A resource referencing a CRD that does not exist yet (dependency ordering issue).

---

## Dynamically Provisioned PVC Fails Flux Dry-Run After Binding

**Symptom:** A PVC that was dynamically provisioned (e.g., by `nfs-kubernetes` StorageClass) causes Flux reconciliation to fail:

```
PersistentVolumeClaim "app-data" is invalid: spec: Forbidden: spec is immutable after creation
```

**Root Cause:** The PVC manifest in Git has `storageClassName: nfs-kubernetes` but no `volumeName`. When the PVC was first created, the provisioner dynamically created a PV and bound it. The PVC in the cluster now has `spec.volumeName: pvc-xxx-xxx`. When Flux runs a dry-run apply, Kubernetes sees the manifest (without `volumeName`) as a request to modify the immutable `spec`, causing a validation error.

**Resolution:** After a PVC is bound to a dynamically provisioned PV, add `volumeName` to the PVC manifest to match the actual binding:

```bash
# Find the PV name
kubectl get pvc -n <namespace> <pvc-name> -o jsonpath='{.spec.volumeName}'
# Returns: pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Then update the PVC manifest:

```yaml
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-kubernetes
  volumeName: pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # Pin after binding
  resources:
    requests:
      storage: 10Gi
```

---

## PV/PVC Deletion Deadlock from Protection Finalizers

**Symptom:** `kubectl delete pv <name>` and `kubectl delete pvc <name>` hang indefinitely. The resources show `Terminating` status but never complete deletion.

**Root Cause:** Kubernetes adds protection finalizers automatically:
- `kubernetes.io/pv-protection` on PersistentVolumes
- `kubernetes.io/pvc-protection` on PersistentVolumeClaims

These finalizers prevent deletion while resources are in use. However, they can deadlock when:
1. The PVC has a finalizer that waits for the pod to stop using it
2. The PV has a finalizer that waits for the PVC to be deleted
3. The pod/deployment referencing them has already been removed but the finalizer controller has not cleaned up

**Resolution:** Patch both resources to remove finalizers, then delete:

```bash
# Remove PVC finalizer
kubectl patch pvc <pvc-name> -n <namespace> -p '{"metadata":{"finalizers":null}}'

# Remove PV finalizer
kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":null}}'

# Both should now terminate immediately
```

After removal, Flux will recreate the PV and PVC from the Git manifests on the next reconciliation cycle.

---

## Flux HelmRepository 404 After Nexus Migration

**Symptom:** All custom Kustomizations stuck `False`/`Unknown`. The `platform-controllers` health check times out on all HelmRepositories. All HelmRepositories pointing to Nexus return `404 Repository not found`.

**Root Cause:** A commit updated all `HelmRepository` `spec.url` values to point at Nexus proxy repos, but the Nexus proxy repos were never created. The script that creates the repos (`scripts/nexus/configure-proxy-repos.sh`) was added at the same time but never executed. Flux applied the manifests immediately on push, source-controller got 404s from Nexus for all repos, and health checks timed out -- cascading failure across the entire `platform-controllers -> platform-configs -> apps` dependency chain.

**Resolution:** Run `scripts/nexus/configure-proxy-repos.sh` (idempotent -- safe to re-run). Then force-annotate HelmRepositories to re-fetch:

```bash
kubectl annotate helmrepository -n flux-system --all \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

**Lesson:** When migrating `HelmRepository` URLs to a new proxy (Nexus or any Helm repo mirror), the proxy repos must exist BEFORE the manifests are merged to the default branch. Otherwise Flux will immediately apply the broken manifests and cascade-fail all dependent Kustomizations. Use a feature branch to test the proxy is reachable before merging.

---

## ESO smtp-credentials Default Login Field Collision

**Symptom:** Multiple apps (`GitLab`, `Linkwarden`, `n8n`) enter `CreateContainerConfigError` after a new SMTP credentials PR is merged. ExternalSecret sync fails with:

```
expected one 1Password ItemField matching: 'username' in 'google-smtp', got 2
```

or

```
expected one 1Password ItemField matching: 'host' in 'google-smtp', got 0
```

**Root Cause:** The ExternalSecret `remoteRef.property` values used `username` and `password`, which collide with the **default Login item fields** on the `google-smtp` 1Password item. The default `username` field on a Login item is NOT addressable by `property` in the same way as custom fields -- ESO either finds 0 matches (for `host`, which is a URL-section field) or finds 2 matches (for `username`, where the default field and a custom field of the same name both exist).

ESO's `property` field resolves by matching `ItemField.label` in the 1Password item JSON. For Login-category items, the default fields (`username`, `password`, `url`) have labels that can collide with or be ambiguous to custom fields of the same name.

**Resolution:**

1. Add custom text fields to the 1Password item with non-colliding names:
   - Add field `smtp-username` (type: text)
   - Add field `smtp-password` (type: concealed)

2. Update ExternalSecret `remoteRef.property` references:
   - `username` -> `smtp-username`
   - `password` -> `smtp-password`

3. The `secretKey` in the resulting K8s Secret can still be `username`/`password` -- only the `property` (source field label) needs to change:

   ```yaml
   data:
     - secretKey: username         # Key in K8s Secret (unchanged)
       remoteRef:
         key: google-smtp
         property: smtp-username   # Custom text field (not the default Login field)
     - secretKey: password
       remoteRef:
         key: google-smtp
         property: smtp-password   # Custom concealed field
   ```

**Lesson:** For any 1Password Login-category item used with ESO, never use `username`, `password`, or URL fields for `remoteRef.property`. Always create custom text fields with unique names (e.g., `smtp-username`, `smtp-password`). Fields like `host`, `port`, `from` that don't collide with default Login fields work fine.

---

## RTX 3060 VFIO Passthrough Crashes gpu-workstation Host

**Symptom:** Starting a VM with `hostpci0: host=0000:65:00.0` (RTX 3060, `10de:2504`) configured causes the gpu-workstation host to crash and reboot within seconds. The crash is repeatable on every VM start attempt. After multiple crashes in quick succession, the machine may stop responding (stuck at POST or in a fast crash loop requiring a power cycle).

dmesg from the first crash:

```
resource: resource sanity check: requesting [mem 0x000c0000-0x000dffff],
  which spans more than PCI Bus 0000:00 [mem 0x000c4000-0x000c7fff window]
caller pci_map_rom+0x6c/0x1b0 mapping multiple BARs
vfio-pci 0000:65:00.0: No more image in the PCI ROM
```

**Root Cause:** The crash has multiple contributing factors:

1. **`rombar=1` (Proxmox default):** QEMU calls `pci_map_rom()` to map the GPU ROM BAR into the VGA legacy region `0x000c0000-0x000dffff`. The host PCI bus window only covers `0x000c4000-0x000c7fff`, creating a resource conflict that triggers a host kernel panic.

2. **EFI framebuffer (sysfb/simplefb) holding GPU BARs:** The EFI stub initialises a framebuffer using the GPU's BARs and marks them as `BOOTFB` reservations. IOMMU/VFIO DMA mapping for those BARs is then blocked.

3. **VGA arbitration:** Without `disable_vga=1` in the vfio-pci module options, the kernel's VGA arbitration code may hold the VGA region open on behalf of vfio-pci, interfering with passthrough.

4. **IOMMU group isolation -- VERIFIED CLEAN:** `vfio-check.sh` confirmed Group 1 contains only `65:00.0` (GPU) and `65:00.1` (audio). No PCIe root ports share the group. ACS override is not needed.

5. **VFIO bus reset crashing host (X299-specific):** With both functions assigned to vfio-pci, VFIO performs a group-level bus reset (both functions simultaneously) in addition to individual FLRs. The audio function (`65:00.1`) has no FLR capability (no `reset_method` sysfs entry), forcing VFIO to fall back to bus reset for the whole group. This bus reset crashes X299/Skylake-X.

6. **Root cause (deepest):** After restricting `65:00.0` to FLR-only, the host survives the VFIO reset phase. The crash then occurs 3-4 minutes into VM boot -- consistent with the **guest NVIDIA driver loading and initialising the GPU via VFIO** (DMA, MSI-X, MMIO BAR mapping through the VFIO interface). The QEMU log is empty before each crash; the fault happens in the host kernel, not QEMU userspace. This is a known incompatibility between RTX 3060 (GA106/Ampere) VFIO initialisation and X299/Skylake-X PCIe handling.

**Hardware confirmed working:** Ubuntu + NVIDIA CUDA drivers run correctly on the same gpu-workstation hardware without Proxmox. The issue is specific to KVM VFIO passthrough.

**Fixes applied (in order):**

```bash
# 1. rombar=0 -- stops the pci_map_rom crash
#    In VM config: hostpci0: 0000:65:00.0,pcie=1,rombar=0
#                  hostpci1: 0000:65:00.1,pcie=1,rombar=0

# 2. initcall_blacklist=sysfb_init -- stops EFI framebuffer holding GPU BARs
#    Add to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then:
update-grub

# 3. disable_vga=1 -- stops VGA arbitration interference
#    Add to /etc/modprobe.d/vfio.conf:
#    options vfio-pci ids=10de:2504,10de:228e disable_vga=1
update-initramfs -u

# 4. FLR-only restriction -- stops bus reset crash on X299
echo "flr" > /sys/bus/pci/devices/0000:65:00.0/reset_method
# Persist via /etc/udev/rules.d/99-vfio-flr.rules:
# ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2504", ATTR{reset_method}="flr"
```

**vendor-reset module: not applicable.** This module only supports AMD GPUs. Building it for NVIDIA provides no benefit and taints the kernel.

**Recommended alternative: LXC + host NVIDIA driver.** Install NVIDIA drivers directly on the gpu-workstation Proxmox host, create a privileged LXC container, and bind-mount `/dev/nvidia*` device nodes into it. This avoids VFIO entirely -- the container shares the host kernel and driver. This works because Ubuntu + NVIDIA works natively on this hardware; the failure mode is specific to KVM VFIO passthrough.

The LXC approach requires:
- `unprivileged = false` on the container (UID remapping breaks cgroup device allow rules)
- `lxc.cgroup2.devices.allow: c 195:* rwm` (nvidia0, nvidiactl)
- `lxc.cgroup2.devices.allow: c 236:* rwm` (nvidia-uvm, nvidia-uvm-tools)
- `lxc.cgroup2.devices.allow: c 10:235 rwm` (nvidia-modeset)
- `lxc.mount.entry` bind-mounts for each `/dev/nvidia*` device node

These fields are not exposed by the bpg/proxmox Terraform provider; write them via `null_resource` SSH to `/etc/pve/lxc/<vmid>.conf`.

**Terraform:** The comfyui module is kept with `gpu_passthrough_enabled = false` until the LXC approach is set up. Always set `gpu_rombar = false` when KVM passthrough is used for compute GPUs.

**PCI IDs:** RTX 3060 VGA: `10de:2504` at `0000:65:00.0`; Audio: `10de:228e` at `0000:65:00.1`.

---

## LXC + NVIDIA 580+ Device Node Changes (gpu-workstation)

**Context:** After abandoning KVM VFIO, the LXC + host NVIDIA driver approach was adopted for gpu-workstation. During implementation, several NVIDIA 580+ driver behavioural changes caused additional failures.

### nvidia-uvm Major Number is Dynamically Assigned

**Symptom:** CUDA fails inside the LXC container. `nvidia-smi` works (uses `/dev/nvidiactl` at major 195), but any CUDA call or `nvidia-smi -L` with device enumeration fails. The `lxc.cgroup2.devices.allow: c 236:* rwm` entry is present but has no effect.

**Root Cause:** In NVIDIA driver 580+, the kernel-assigned major device number for `nvidia-uvm` is dynamically allocated by the kernel at module load time. On kernel 6.17 with this driver, the major is `510`, not `236`. The `236` value was a convention used in older kernels/drivers. Using `c 236:* rwm` grants access to the wrong character device class entirely.

**Resolution:** Read the actual major at runtime:

```bash
cat /sys/module/nvidia_uvm/parameters/uvm_dev_major
# Returns: 510 (on kernel 6.17 + NVIDIA 580.x)
```

For a trusted privileged container, the simplest fix is `c *:* rwm` (allow all character devices). For a more targeted allow list, use the dynamic value:

```bash
UVM_MAJOR=$(cat /sys/module/nvidia_uvm/parameters/uvm_dev_major)
echo "lxc.cgroup2.devices.allow: c ${UVM_MAJOR}:* rwm" >> /etc/pve/lxc/<vmid>.conf
```

Update Terraform `null_resource` provisioners to read the major dynamically rather than hardcoding `236`.

### /dev/nvidia-modeset Does Not Exist as Standalone Device

**Symptom:** `lxc.mount.entry` for `/dev/nvidia-modeset` causes a warning or silent failure on container start. The device does not appear in `/dev/` on the host.

**Root Cause:** In NVIDIA 580+, the modeset interface is accessed via `ioctl` on `/dev/nvidiactl` (major 195). There is no separate `/dev/nvidia-modeset` character device node. The `c 10:235 rwm` cgroup entry and the `nvidia-modeset` bind-mount entry from older documentation are unnecessary and will generate errors.

**Resolution:** Remove the `nvidia-modeset` `lxc.mount.entry` and `lxc.cgroup2.devices.allow: c 10:235 rwm` lines. Verify with `ls -la /dev/nvidia*` on the host after driver install to confirm which devices actually exist.

### nvidia-uvm Nodes Created Lazily

**Symptom:** `/dev/nvidia-uvm` and `/dev/nvidia-uvm-tools` do not exist on the host when the LXC container starts. The bind-mount entries with `optional` silently succeed (no error), but CUDA calls fail inside the container because the device files were never created.

**Root Cause:** The `nvidia-uvm` kernel module creates its device nodes lazily -- they only appear in `/dev/` after the first userspace access. This is typically triggered by `nvidia-smi` or any CUDA runtime call. If no process has accessed the nvidia-uvm interface before the container starts its CUDA workload, the bind-mounts point at non-existent host device nodes.

**Resolution:** Create a systemd oneshot service on the Proxmox host to force device node creation before any LXC containers start:

```ini
# /etc/systemd/system/nvidia-uvm-init.service
[Unit]
Description=Initialise NVIDIA UVM device nodes
Before=lxc.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable nvidia-uvm-init.service
```

After the first `nvidia-smi` run, `/dev/nvidia-uvm` and `/dev/nvidia-uvm-tools` will exist persistently until the next host reboot (at which point the service runs again on boot).

---

## pct exec Host Crashes on Kernel 6.17 + X299 (Privileged LXC)

**Symptom:** Running `pct exec <vmid> -- apt-get install -y <packages>` against a privileged LXC container on gpu-workstation (ASRock X299 Taichi, kernel 6.17.x-pve) causes the host to kernel panic or crash within seconds of the container workload starting. The crash is repeatable -- it always occurs during `pct exec` workloads, never when the host is idle or when SSH-ing directly into the container. No useful dmesg is captured before the crash (machine check / instant reboot).

**Root Cause:** Unknown. Suspected interaction between cgroup2, privileged LXC namespaces, and X299/Skylake-X PCIe or memory handling on kernel 6.17. BIOS update from P1.70 to P2.50 on the ASRock X299 Taichi did NOT resolve the crash pattern.

**Resolution (avoidance):** Do not use `pct exec` for package installation or any apt workloads on gpu-workstation. Instead:

1. **SSH directly into the container** (`ssh root@<container-ip>`) -- the crash only occurs via the `pct exec` path, not direct SSH
2. **Run Docker directly on the PVE host** without a container intermediary -- avoids all LXC namespace issues while keeping the node in the Proxmox cluster

The Docker-on-PVE-host approach works because Ubuntu + NVIDIA runs correctly on gpu-workstation hardware natively. The failure is specific to LXC container interactions on this hardware/kernel combination.

---

## vendor-reset Module Causes Spontaneous Host Crashes on NVIDIA Systems

**Symptom:** After installing the `vendor-reset` DKMS module (sometimes suggested for GPU reset stability in VFIO/passthrough setups), the gpu-workstation host begins crashing spontaneously -- not just during GPU operations but during unrelated activity. Removing the module stops the crashes.

**Root Cause:** The `vendor-reset` kernel module implements GPU reset sequences for AMD GPUs (specifically RX 5700 and similar). It has no implementation for NVIDIA GPUs. Despite this, loading the module on a system with NVIDIA GPUs introduces kernel-level instability on some hardware (likely due to PCI subsystem hooks that conflict with the NVIDIA driver).

**Resolution:** Remove completely:

```bash
dkms remove vendor-reset/0.1.1 --all
apt-get remove --purge dkms-vendor-reset  # or however it was installed
```

Do not install `vendor-reset` on any host running NVIDIA drivers. It provides no benefit for NVIDIA and actively causes harm on some hardware.

---

## Summary: Issue Status and Fix Locations

| # | Issue | Status | Fix Location | Effort |
|---|-------|--------|------------|--------|
| 1 | K3s token format | CRITICAL | 1Password item | Update field value |
| 2 | write_files owner ordering | FIXED | agent + postgresql templates | Add `defer: true` |
| 3 | VLAN double-tagging | FIXED | k3s-cluster.tf | Remove `vlan_id` |
| 4 | Missing qemu-guest-agent | FIXED | All 3 templates | Add to packages |
| 5 | Wrong DNS servers | FIXED | k3s-cluster.tf | Change to Google DNS |
| 6 | No console password | DEFERRED | All 3 templates | Add `chpasswd:` block |
| 7 | ESO CRD conflict | FIXED | external-secrets.yaml | `install.crds: Skip` |
| 8 | Connect DNS failure | FIXED | cluster-secret-store.yaml | Use LAN IP (VIP) |
| 9 | Dev vault inaccessible | FIXED | cluster-secret-store.yaml | Remove Dev vault |
| 10 | Loki StatefulSet immutable | FIXED | Manual: delete Helm secrets | Fresh install |
| 11 | K3s /readyz returns 401 | RESOLVED | Health check scripts | Accept 401/403 as healthy |
| 12 | Flux SSH vs HTTPS URL mismatch | REFERENCE | gotk-sync.yaml / bootstrap | Re-bootstrap with matching auth method |
| 13 | NFS mount access denied after IP change | REFERENCE | NAS NFS permissions | Use CIDR range or static IPs |
| 14 | StatefulSet immutable from downgrade/rollback | REFERENCE | HelmRelease or manual | `upgrade.force: true` or delete StatefulSet |
| 15 | Keepalived interface name mismatch | FIXED | cloud-init templates + running VMs | Change `ens18` to `eth0` |
| 16 | Keepalived health check deadlock | FIXED | pg-health-check.sh + cloud-init templates | Only check `pg_isready` |
| 17 | Premature standby promotion | REFERENCE | Deployment order | Install keepalived on MASTER first |
| 18 | Homepage widget errors (service name, API token, image version) | REFERENCE | release.yaml + 1Password | See "Homepage Widget Debugging Patterns" section |
| 19 | GitHub Actions exporter probe failure (CrashLoopBackOff) | FIXED | deployment.yaml | Switch httpGet to tcpSocket; delete + recreate (probe type change) |
| 20 | Flux Kustomization blocked by single failing resource (atomicity) | REFERENCE | Kustomization resources list | Fix or remove failing resource to unblock |
| 21 | Dynamically provisioned PVC fails Flux dry-run after binding | REFERENCE | PVC manifest | Add `volumeName` to match bound PV |
| 22 | PV/PVC deletion deadlock from protection finalizers | REFERENCE | kubectl patch | Remove finalizers from both PV and PVC |
| 23 | Flux HelmRepository 404 after Nexus migration | FIXED | Run configure-proxy-repos.sh before merge | Create proxy repos first, then merge |
| 24 | ESO smtp-credentials default Login field collision | FIXED | ExternalSecret property names | Use custom text fields, not default Login fields |
| 25 | RTX 3060 VFIO passthrough crashes gpu-workstation host | RESOLVED -- KVM VFIO abandoned; LXC + host driver approach adopted | hostpci config + GRUB + modprobe + udev (historical); use LXC + host NVIDIA driver going forward |
| 26 | LXC + NVIDIA 580+ uvm major number dynamic (510, not 236) | REFERENCE | /etc/pve/lxc/\<vmid\>.conf | Read major from /sys/module/nvidia_uvm/parameters/uvm_dev_major |
| 27 | /dev/nvidia-modeset not a standalone device in NVIDIA 580+ | REFERENCE | /etc/pve/lxc/\<vmid\>.conf | Remove nvidia-modeset bind-mount and c 10:235 cgroup entry |
| 28 | nvidia-uvm nodes created lazily (CUDA fails on first container start) | REFERENCE | Proxmox host systemd | Add nvidia-uvm-init.service Before=lxc.service to force device creation |
| 29 | pct exec crashes host on kernel 6.17 + X299 (privileged LXC) | WORKAROUND -- use SSH into container or Docker on PVE host directly | n/a -- root cause unknown; BIOS P2.50 did not fix | SSH into container directly or use Docker on PVE host |
| 30 | vendor-reset DKMS module causes spontaneous crashes on NVIDIA hosts | FIXED | Remove dkms vendor-reset module entirely | `dkms remove vendor-reset/0.1.1 --all` |
