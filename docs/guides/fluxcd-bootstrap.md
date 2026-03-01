# Guide: Bootstrapping FluxCD for GitOps

This guide covers how to bootstrap FluxCD (Flux v2) on your K3s cluster, set up the repository
structure for GitOps, configure SOPS + age for encrypted secrets, and deploy initial infrastructure
components (cert-manager, ingress-nginx).

## Prerequisites

- A running K3s cluster (see [Ansible K3s Provisioning](./ansible-k3s-provisioning.md))
- `kubectl` configured to access the cluster (`KUBECONFIG` pointing to your k3s config)
- A GitHub account and personal access token (PAT)
- `flux` CLI installed on your workstation

## Key documentation

| Topic | URL |
|---|---|
| FluxCD installation overview | https://fluxcd.io/flux/installation/ |
| Bootstrap for GitHub | https://fluxcd.io/flux/installation/bootstrap/github/ |
| `flux bootstrap github` CLI reference | https://fluxcd.io/flux/cmd/flux_bootstrap_github/ |
| Repository structure guide | https://fluxcd.io/flux/guides/repository-structure/ |
| SOPS + age secrets guide | https://fluxcd.io/flux/guides/mozilla-sops/ |
| Kustomization CRD reference | https://fluxcd.io/flux/components/kustomize/kustomizations/ |
| HelmRelease CRD reference | https://fluxcd.io/flux/components/helm/helmreleases/ |
| flux2-kustomize-helm-example | https://github.com/fluxcd/flux2-kustomize-helm-example |
| cert-manager Helm chart | https://cert-manager.io/docs/installation/helm/ |
| ingress-nginx Helm chart | https://kubernetes.github.io/ingress-nginx/deploy/ |

---

## Step 1: Install the Flux CLI

**What you're doing:** Installing the `flux` command-line tool on your workstation. You only
need this for bootstrap and debugging — after that, all changes go through Git.

```bash
# Linux
curl -s https://fluxcd.io/install.sh | sudo bash

# macOS (Homebrew)
brew install fluxcd/tap/flux

# Verify
flux --version
```

Check that your cluster is compatible:

```bash
flux check --pre
```

This validates that your K3s cluster meets Flux requirements (Kubernetes version, RBAC, etc.).

**Docs:** https://fluxcd.io/flux/installation/#install-the-flux-cli

---

## Step 2: Create a GitHub personal access token

**What you're doing:** Creating a token that Flux will use to read from and write to your
GitHub repository.

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)** or use a **Fine-grained token**
3. For a classic token, select the `repo` scope (full control of private repositories)
4. For a fine-grained token, select:
   - **Administration:** Read-only (or Read-write if the repo doesn't exist yet)
   - **Contents:** Read and write
   - **Metadata:** Read-only

Save the token — you'll need it in the next step.

**Docs:** https://fluxcd.io/flux/installation/bootstrap/github/#github-personal-access-token

---

## Step 3: Bootstrap Flux

**What you're doing:** Running a single command that:
1. Deploys Flux controllers to your cluster (in the `flux-system` namespace)
2. Creates or configures a GitHub repository as the GitOps source of truth
3. Commits Flux manifests to the repository
4. Configures Flux to manage itself via Git (self-updating)

```bash
export GITHUB_TOKEN=<your-pat-here>

flux bootstrap github \
  --token-auth \
  --owner=homelab-admin \
  --repository=homelab-iac \
  --branch=main \
  --path=clusters/homelab \
  --personal
```

Or use the bootstrap script (does pre-flight checks + validation):

```bash
export GITHUB_TOKEN=<your-pat-here>
./scripts/k8s/bootstrap-flux.sh
```

| Flag | Value | Why |
|------|-------|-----|
| `--token-auth` | (flag) | Use HTTPS + PAT instead of SSH keys |
| `--owner` | `homelab-admin` | Your GitHub username |
| `--repository` | `homelab-iac` | This repository |
| `--branch` | `main` | Target branch |
| `--path` | `clusters/homelab` | Flux entry point for the Asgard cluster (see [architecture](../architecture/flux-structure.md)) |
| `--personal` | (flag) | Personal account (not an organization) |

**What gets created in the cluster:**
- `flux-system` namespace with 4 controller deployments:
  - `source-controller` — fetches Git repos, Helm charts, OCI artifacts
  - `kustomize-controller` — applies Kustomize manifests
  - `helm-controller` — manages HelmReleases
  - `notification-controller` — handles events and alerts
- A `flux-system` Secret containing your GitHub PAT
- A `GitRepository` resource pointing to your repo
- A `Kustomization` resource watching the `--path` directory

**What gets committed to GitHub:**
```
clusters/homelab/
└── flux-system/
    ├── gotk-components.yaml      # All Flux CRDs and controller manifests
    ├── gotk-sync.yaml            # GitRepository + Kustomization resources
    └── kustomization.yaml        # Standard Kustomize file listing resources
```

Verify it worked:

```bash
# Check all Flux controllers are running
flux check

# Check Flux resources
flux get all

# Check pods
kubectl get pods -n flux-system
```

**Docs:** https://fluxcd.io/flux/installation/bootstrap/github/

---

## Step 4: Repository structure

**What you're doing:** Understanding how the GitOps repository is organized so infrastructure
and applications deploy in the correct order with proper dependencies.

> For the full architecture rationale, see [docs/architecture/flux-structure.md](../architecture/flux-structure.md).

This repo uses the [Flux community monorepo pattern](https://fluxcd.io/flux/guides/repository-structure/)
with three top-level directories, each with a single responsibility:

```
clusters/                  # HOW to deploy (Flux orchestration)
└── homelab/                # Production cluster entry point
    ├── flux-system/       # Auto-generated by bootstrap
    ├── platform.yaml      # Kustomization → ./kubernetes/platform/...
    ├── apps.yaml          # Kustomization → ./kubernetes/apps
    └── monitoring.yaml    # Kustomization → ./kubernetes/platform/monitoring/...

kubernetes/                # WHAT to deploy (K8s manifests)
├── apps/                  # Application HelmReleases
│   ├── podinfo/
│   └── plex/
└── platform/              # Infrastructure services
    ├── controllers/       # cert-manager, ingress-nginx
    ├── configs/           # ClusterIssuers
    └── monitoring/        # kube-prometheus-stack, loki

infrastructure/            # WHERE to deploy (Terraform — VMs, Proxmox)
```

### Cluster-level Kustomizations

These files in `clusters/homelab/` tell Flux **what to reconcile and in what order**:

**`clusters/homelab/platform.yaml`** — deploys controllers first, then configs:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-controllers
  namespace: flux-system
spec:
  interval: 1h
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/platform/controllers
  prune: true
  wait: true
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-configs
  namespace: flux-system
spec:
  dependsOn:
    - name: platform-controllers
  interval: 1h
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/platform/configs
  prune: true
```

**`clusters/homelab/apps.yaml`** — depends on platform being ready:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m0s
  dependsOn:
    - name: platform-configs
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/apps
  prune: true
  wait: true
  timeout: 5m0s
```

**The dependency chain:** `platform-controllers` -> `platform-configs` -> `apps`

This ensures cert-manager CRDs exist before ClusterIssuers are created, and infrastructure
is running before applications deploy.

**Docs:**
- [Repository structure](https://fluxcd.io/flux/guides/repository-structure/)
- [Kustomization dependencies](https://fluxcd.io/flux/components/kustomize/kustomizations/#dependencies)

---

## Step 5: Deploy cert-manager

**What you're doing:** Adding cert-manager as the first infrastructure controller. It automates
TLS certificate management via Let's Encrypt.

### Add the Helm source

**`kubernetes/platform/sources/jetstack.yaml`:**

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

### Add the HelmRelease

**`kubernetes/platform/controllers/cert-manager/namespace.yaml`:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
```

**`kubernetes/platform/controllers/cert-manager/release.yaml`:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 30m
  chart:
    spec:
      chart: cert-manager
      version: "1.x"       # Pin to a specific minor version in production
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  install:
    crds: Create
    remediation:
      retries: 3
  upgrade:
    crds: CreateReplace
    remediation:
      retries: 3
  values:
    installCRDs: true
```

**`kubernetes/platform/controllers/cert-manager/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - release.yaml
```

### Add the ClusterIssuer

**`kubernetes/platform/configs/cluster-issuer.yaml`:**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com          # Change this
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

> **Note:** For a homelab behind NAT, HTTP-01 challenges require port 80 forwarded to your
> ingress controller. Alternatively, use DNS-01 challenges with a supported DNS provider.
>
> Docs: https://cert-manager.io/docs/configuration/acme/

---

## Step 6: Deploy ingress-nginx

**What you're doing:** Adding an ingress controller so external HTTP/HTTPS traffic can reach
your cluster services.

**`kubernetes/platform/sources/ingress-nginx.yaml`:**

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes.github.io/ingress-nginx
```

**`kubernetes/platform/controllers/ingress-nginx/namespace.yaml`:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
```

**`kubernetes/platform/controllers/ingress-nginx/release.yaml`:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 30m
  chart:
    spec:
      chart: ingress-nginx
      version: "4.x"       # Pin to a specific minor version in production
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    controller:
      replicaCount: 2
      service:
        type: LoadBalancer    # Or NodePort if not using MetalLB/kube-vip
```

**`kubernetes/platform/controllers/ingress-nginx/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - release.yaml
```

Don't forget the parent kustomization:

**`kubernetes/platform/controllers/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager
  - ingress-nginx
```

**`kubernetes/platform/sources/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jetstack.yaml
  - ingress-nginx.yaml
```

**`kubernetes/platform/configs/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cluster-issuer.yaml
```

---

## Step 7: Configure SOPS + age for secrets

**What you're doing:** Setting up encrypted secrets so you can safely commit Kubernetes Secrets
to Git. Flux automatically decrypts them during reconciliation.

### Generate an age keypair

```bash
# Install age if not present
# Ubuntu/Debian: sudo apt install age
# macOS: brew install age

# Generate keypair
age-keygen -o age.agekey

# Output:
# Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# (save this — you'll use it to encrypt)
```

**Keep `age.agekey` safe.** This is the private key. Back it up securely (e.g., 1Password).
Never commit it to Git.

### Store the private key in the cluster

```bash
cat age.agekey | \
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
```

Requirements:
- Secret name **must** be `sops-age`
- File key **must** end in `.agekey`
- Must be in `flux-system` namespace

### Create a `.sops.yaml` config

Place this at the root of your repository to define encryption rules:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*\.sops\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Replace the age public key with yours.

### Encrypt a secret

```bash
# Create a Kubernetes secret manifest (plaintext)
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=changeme \
  --namespace=default \
  --dry-run=client -o yaml > my-secret.sops.yaml

# Encrypt it with SOPS
sops --encrypt --in-place my-secret.sops.yaml
```

The file is now safe to commit — only the `data` and `stringData` fields are encrypted.
Metadata (name, namespace, labels) remains in plaintext so Flux can read it.

### Enable decryption in Flux Kustomizations

Add `decryption` to any Flux `Kustomization` that contains encrypted secrets:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  # ... existing config ...
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

Flux will now automatically decrypt any SOPS-encrypted files it encounters in that path.

**Docs:** https://fluxcd.io/flux/guides/mozilla-sops/

---

## Step 8: Commit and push

**What you're doing:** Pushing all the new manifests to Git so Flux picks them up.

```bash
git add -A
git commit -m "feat: add infrastructure controllers (cert-manager, ingress-nginx)"
git push
```

Watch Flux reconcile:

```bash
# Watch Kustomizations
flux get kustomizations --watch

# Watch HelmReleases
flux get helmreleases -A

# Check events if something fails
flux events
```

All resources should eventually show `Ready: True`.

---

## Troubleshooting

### Flux reconciliation stuck

```bash
# Force reconciliation
flux reconcile kustomization flux-system --with-source

# Check source status
flux get sources git

# Check controller logs
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller
```

### HelmRelease not installing

```bash
# Check HelmRelease status
flux get helmreleases -A

# Describe for events
kubectl describe helmrelease cert-manager -n cert-manager

# Check if HelmRepository is accessible
flux get sources helm -A
```

### SOPS decryption failing

```bash
# Verify the sops-age secret exists
kubectl get secret sops-age -n flux-system

# Check kustomize-controller logs for decrypt errors
kubectl logs -n flux-system deploy/kustomize-controller | grep -i sops
```

**Docs:** https://fluxcd.io/flux/cheatsheets/troubleshooting/

---

---

## Future: 1Password integration with External Secrets Operator

The SOPS + age approach above encrypts secrets in Git. An alternative (or complement) is the
**External Secrets Operator (ESO)** with 1Password as the backend. ESO syncs secrets from
1Password into Kubernetes Secrets at runtime — no encrypted files in Git needed.

### Why use both SOPS and ESO

Use **SOPS for one thing only**: encrypting the bootstrap secret (the 1Password Connect token
that ESO needs to authenticate). After that, ESO handles everything else:

```
SOPS + age  →  Decrypts Connect token  →  ESO authenticates  →  All other secrets from 1Password
```

### Adding ESO to the Flux dependency chain

ESO fits into the existing `sources → controllers → configs → apps` chain:

1. Add `external-secrets` HelmRepository to `infrastructure/sources/`
2. Add `external-secrets` HelmRelease to `infrastructure/controllers/`
3. Add `ClusterSecretStore` (pointing to 1Password Connect) to `infrastructure/configs/`
4. Add `ExternalSecret` resources alongside your applications in `apps/`

The `dependsOn` chain ensures CRDs exist before SecretStores, and SecretStores exist before
ExternalSecrets.

### Quick example

```yaml
# After ESO is deployed, create ExternalSecrets for your apps
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: My App Database       # 1Password item title
        property: url
```

See [Guide 6: 1Password Secrets Management](./1password-secrets-management.md) for the full
deployment walkthrough including Helm charts, SecretStore configuration, and the bootstrap
problem.

---

## What's next

After Flux is running with cert-manager and ingress-nginx:

1. **Deploy External Secrets Operator** — See [Guide 6: 1Password Secrets Management](./1password-secrets-management.md#part-6-fluxcd--eso-deployment)
2. **Deploy monitoring** — Prometheus + Grafana via Flux HelmReleases
3. **Deploy Reloader** — Automatically restarts pods when ConfigMaps/Secrets change
4. **Deploy applications** — Add your workloads to the `apps/` directory
5. **Set up notifications** — Configure Flux alerts to Slack/Discord
