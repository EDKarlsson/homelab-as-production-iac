# Nexus Repository Configuration

## Status

### 1. Proxy Repositories — DONE (PR #115, Session 29)

13 proxy repositories created via `scripts/nexus/configure-proxy-repos.sh`:

| Name | Format | Upstream |
|------|--------|----------|
| apt-ubuntu | apt | archive.ubuntu.com/ubuntu |
| apt-ubuntu-security | apt | security.ubuntu.com/ubuntu |
| docker-hub | docker | registry-1.docker.io |
| docker-ghcr | docker | ghcr.io |
| docker-quay | docker | quay.io |
| go-proxy | go | proxy.golang.org |
| helm-stable | helm | charts.helm.sh/stable |
| npm-proxy | npm | registry.npmjs.org |
| pypi-proxy | pypi | pypi.org |
| cargo-proxy | cargo | index.crates.io |
| gitlfs-github | raw | github.com |
| huggingface | raw | huggingface.co |
| terraform-registry | raw | registry.terraform.io |

ExternalSecret `nexus-admin-credentials` added for API access.
1Password item `nexus-repository` updated with custom text fields for ESO.

### 2. Connect logging to Grafana — TODO

### 3. Connect to GitHub, TeamCity, GitLab for build artifacts — TODO
- Can use [Tailscale GH Action](https://github.com/marketplace/actions/connect-tailscale)

## Next: Migrate Services to Use Nexus Proxies

Once proxy repos are created, services need to be reconfigured to pull through Nexus.

### Migration candidates (by priority)

| Priority | Consumer | Proxy Repos | What Changes | Scope |
|----------|----------|-------------|-------------|-------|
| High | K3s nodes (containerd) | docker-hub, docker-ghcr, docker-quay | containerd mirror config on all 8 nodes | Ansible role change |
| High | K3s VMs (apt) | apt-ubuntu, apt-ubuntu-security | `/etc/apt/sources.list.d/` on all VMs | cloud-init or Ansible |
| Medium | Flux HelmRepositories | helm-stable | Update `spec.url` in HelmRepository manifests | Kubernetes manifests |
| Medium | TeamCity build agents | npm-proxy, pypi-proxy, go-proxy, cargo-proxy | Build agent env vars / tool configs | K8s ConfigMaps |
| Low | JupyterLab | pypi-proxy | `pip.conf` in container | Dockerfile or ConfigMap |
| Low | Terraform providers | terraform-registry | `TF_CLI_CONFIG_FILE` or `.terraformrc` | Dev environment |

### Docker/containerd migration (highest value)

Caches ALL image pulls across the cluster. Requires:
1. Ansible role to configure containerd mirrors on each K3s node
2. Each mirror entry points to Nexus: `http://nexus-nexus-repository-manager.nexus.svc.cluster.local:8081/repository/<repo-name>/`
3. Restart containerd after config change
4. Test: pull an image, verify it appears in Nexus proxy cache

### Notes

- Nexus API reference: https://help.sonatype.com/en/api-reference.html
- Nexus Swagger UI: `http://localhost:8081/#admin/system/api` (via port-forward)
- Script is idempotent — safe to re-run after data loss to restore all proxy repos
