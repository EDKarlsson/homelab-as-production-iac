---
title: Namespace-Based Staging Environment
description: How to deploy and test app changes in a staging namespace on the same K3s cluster, using Kustomize overlays over the production app bases.
tags: [kubernetes, kustomize, flux, staging, gitops]
---

# Namespace-Based Staging Environment

A lightweight staging environment that lives in the same K3s cluster as production,
using separate namespaces (`<app>-staging`) and Kustomize overlays to reuse all
production manifests without duplicating them.

## Architecture

```
git repo
  └── kubernetes/
      ├── apps/           ← production (unchanged)
      │   └── n8n/        ← base: namespace=n8n, host=n8n.10.0.0.201.nip.io
      └── staging/        ← staging overlays
          └── n8n/        ← overlay: namespace=n8n-staging, host=n8n-staging.10.0.0.201.nip.io

Flux
  └── apps Kustomization       → kubernetes/apps   (existing)
  └── staging Kustomization    → kubernetes/staging (new)
```

Each staging overlay:
- **References** the production base (`../../apps/<app>`)
- **Patches** namespace name, ingress hostname, TLS secret name
- **Optionally** patches resource limits, replica count, or Helm values

This means you maintain one set of manifests. Changes to the prod base automatically
propagate to staging on the next Flux reconcile.

## Files Created (Scaffolding Already Done)

| File | Purpose |
|------|---------|
| `clusters/homelab/staging.yaml` | Flux Kustomization entry point for staging |
| `kubernetes/staging/kustomization.yaml` | Root — lists active staging apps |
| `kubernetes/staging/podinfo/kustomization.yaml` | Complete example overlay (podinfo) |

## How to Add an App to Staging

### Step 1: Create the overlay directory

```bash
mkdir -p kubernetes/staging/<app>
```

### Step 2: Write the overlay kustomization

Create `kubernetes/staging/<app>/kustomization.yaml` (template below).

### Step 3: Activate it in the staging root

Edit `kubernetes/staging/kustomization.yaml` and add your app:

```yaml
resources:
  - ./podinfo   # example already here
  - ./<app>     # add your app
```

### Step 4: Validate before committing

```bash
kubectl kustomize kubernetes/staging/<app>
```

Check the output: namespace should be `<app>-staging`, ingress host should be
`<app>-staging.10.0.0.201.nip.io`.

### Step 5: Commit and push

Flux picks it up within 10 minutes (the `staging` Kustomization has `interval: 10m`).
Force immediate reconcile:

```bash
flux reconcile kustomization staging --with-source
```

---

## Overlay Template

Copy this into `kubernetes/staging/<app>/kustomization.yaml` and fill in the
`TODO` items:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../apps/<app>          # TODO: replace <app> with the app directory name

# Override metadata.namespace on all namespaced resources.
# Does NOT rename the Namespace resource itself — that needs the patch below.
namespace: <app>-staging      # TODO: replace <app>

patches:
  # 1. Rename the Namespace resource.
  #    The namespace: field above patches metadata.namespace on other resources,
  #    but Namespace.metadata.name is cluster-scoped and must be patched here.
  - target:
      kind: Namespace
      name: <app>             # TODO: replace <app>
    patch: |-
      - op: replace
        path: /metadata/name
        value: <app>-staging  # TODO: replace <app>

  # 2. Patch the ingress hostname and TLS.
  #    (Skip this block if the app has no ingress.yaml)
  - target:
      kind: Ingress
      name: <app>             # TODO: replace <app>
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: <app>-staging.10.0.0.201.nip.io   # TODO: replace <app>
      - op: replace
        path: /spec/tls/0/hosts/0
        value: <app>-staging.10.0.0.201.nip.io   # TODO: replace <app>
      - op: replace
        path: /spec/tls/0/secretName
        value: <app>-staging-tls                    # TODO: replace <app>

  # 3. (Optional) Drop OAuth2 auth annotations for staging so you don't
  #    need to go through Keycloak while testing.
  #    Only needed for apps that have the oauth2-proxy annotations in ingress.yaml.
  - target:
      kind: Ingress
      name: <app>             # TODO: replace <app>
    patch: |-
      - op: remove
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-url
      - op: remove
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
      - op: remove
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-response-headers

  # 4. (Optional) Skip the Tailscale ingress in staging — saves operator quota.
  #    Use this if the app has a tailscale-ingress.yaml in the base.
  - target:
      kind: Ingress
      name: <app>-tailscale   # TODO: verify name matches tailscale-ingress.yaml
    patch: |-
      - op: replace
        path: /metadata/annotations/tailscale.com~1experimental-forward-cluster-traffic-via-ingress
        value: "false"
  # OR to remove it entirely:
  # patches:
  #   - target:
  #       kind: Ingress
  #       name: <app>-tailscale
  #     patch: |-
  #       $patch: delete
  #       apiVersion: networking.k8s.io/v1
  #       kind: Ingress
  #       metadata:
  #         name: <app>-tailscale

  # 5. (Optional) Reduce replicas or resource requests for staging.
  #    Only useful for Deployments (not HelmReleases — patch values instead).
  - target:
      kind: Deployment
      name: <app>             # TODO: replace <app>
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1

  # 6. (Optional) Override Helm values for staging.
  #    Only for apps using a HelmRelease.
  - target:
      kind: HelmRelease
      name: <app>             # TODO: replace <app>
    patch: |-
      - op: add
        path: /spec/values/replicaCount
        value: 1
```

> **Note on ExternalSecrets**: By default, the staging overlay will use the **same
> 1Password items** as production (same `secretName` in the ExternalSecret, same
> key references). This is fine for most testing. If you need staging-specific
> secrets, add a patch on the `ExternalSecret` resource to point to a different
> 1Password item or different field names.

---

## Complete Example: podinfo

`kubernetes/staging/podinfo/kustomization.yaml` is already in the repo and validated.
It demonstrates the minimal case (no ingress, no secrets):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../apps/podinfo

namespace: podinfo-staging

patches:
  - target:
      kind: Namespace
      name: podinfo
    patch: |-
      - op: replace
        path: /metadata/name
        value: podinfo-staging
```

Build output:
```bash
kubectl kustomize kubernetes/staging/podinfo
# → Namespace: podinfo-staging
# → HelmRelease: podinfo, namespace: podinfo-staging
# → HelmRepository: podinfo, namespace: podinfo-staging
```

---

## Your First Real App Overlay

Pick an app you want to test changes on. Good first candidates:

| App | Why | Complexity |
|-----|-----|------------|
| `wikijs` | Safe, no side effects, has ingress + secret | Medium |
| `homepage` | Instant visual feedback | Low |
| `n8n` | Has OAuth, ingress, secrets — good challenge | High |

**Suggested first exercise**: write the overlay for `wikijs`.

1. Check what it has: `ls kubernetes/apps/wikijs/`
2. Read its `ingress.yaml` to find the hostname and TLS fields
3. Check `external-secret.yaml` to decide if you need to patch ExternalSecret
4. Write `kubernetes/staging/wikijs/kustomization.yaml` using the template above
5. Validate: `kubectl kustomize kubernetes/staging/wikijs`
6. Add `- ./wikijs` to `kubernetes/staging/kustomization.yaml`
7. Run the full staging build: `kubectl kustomize kubernetes/staging`

---

## Removing an App from Staging

1. Comment out or delete the line in `kubernetes/staging/kustomization.yaml`
2. Flux `prune: true` will delete the staging namespace and all its resources within the next reconcile interval

---

## Reference Documentation

- [Kustomize overlays](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/) — official reference for all Kustomization fields
- [Kustomize JSON 6902 patches](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/) — the `patches:` field with target selectors
- [Kustomize namespace transformer](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/namespace/) — how `namespace:` interacts with Namespace resources
- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/) — `interval`, `prune`, `dependsOn`, `path` fields
- [Flux multi-tenancy example](https://github.com/fluxcd/flux2-multi-tenancy) — real-world overlay patterns at scale
- [Kustomize bases and overlays guide](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#bases-and-overlays) — Kubernetes docs walkthrough
- [RFC 6902 JSON Patch](https://datatracker.ietf.org/doc/html/rfc6902) — spec for `op: replace/add/remove` patches (tilde-encoding: `/` → `~1`, `~` → `~0`)

---

## Troubleshooting

**`kubectl kustomize` fails with "no matches for kind"**
- Usually means the patch `target` name doesn't match — check `metadata.name` in the base resource exactly.

**Flux reconciles but namespace doesn't appear**
- Check: `flux get kustomization staging` — look for error messages
- Check: `kubectl get events -n flux-system` for reconcile errors

**Ingress shows 404 or SSL error**
- cert-manager needs to issue a new certificate for the staging hostname. Check:
  `kubectl get certificate -n <app>-staging`
  `kubectl describe certificaterequest -n <app>-staging`

**ExternalSecret fails in staging**
- If the ExternalSecret target `name` was patched but 1Password item doesn't exist yet,
  ESO will error. Either patch the ExternalSecret to point to the prod item or create
  a staging item in 1Password first.

**Patch path not found error**
- The JSON pointer path doesn't exist in the resource. Use `kubectl kustomize` locally
  to inspect the base output and verify paths before committing.
