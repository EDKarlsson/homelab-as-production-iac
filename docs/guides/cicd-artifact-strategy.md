---
title: CI/CD Artifact Strategy and Nexus Layout
description: Artifact scope, Nexus repository topology, and naming/versioning conventions for homelab CI/CD
published: true
date: 2026-02-19
tags:
  - ci
  - cd
  - nexus
  - artifacts
  - conventions
---

# CI/CD Artifact Strategy and Nexus Layout

This guide defines what artifacts are produced by CI/CD, where they live in Nexus, and how they are versioned.

## Scope

Phase 2 artifact pipeline standardizes three artifact classes:

1. **Container images (OCI)** for custom tools/services.
2. **Helm OCI artifacts** for in-house charts.
3. **Raw bundles** (`.tar.gz`, SBOMs, reports, generated assets) for operational outputs.

## Nexus Endpoints

- LAN UI/API: `https://nexus.10.0.0.201.nip.io`
- Tailscale UI/API: `https://nexus.homelab.ts.net`

Use the same hostname per workflow run (do not mix LAN and Tailscale within one job).

## Repository Layout

Create these Nexus repositories:

| Repo Name | Type | Purpose | Write Access |
|---|---|---|---|
| `docker-homelab-hosted` | Docker (hosted) | Internal OCI images | CI only |
| `docker-hub-proxy` | Docker (proxy) | Cache upstream Docker Hub pulls | Read-only |
| `docker-homelab-group` | Docker (group) | Unified pull endpoint (`hosted + proxy`) | None |
| `oci-helm-homelab-hosted` | OCI/Helm (hosted) | Internal Helm charts (OCI) | CI only |
| `raw-ci-hosted` | Raw (hosted) | Script bundles, SBOMs, reports, manifests | CI only |

## Naming and Versioning Conventions

### OCI images

- Image path: `docker-homelab-group/homelab/<component>`
- Required tags:
  - `sha-<git_sha7>` (immutable build identity)
  - `pr-<pr_number>-<git_sha7>` for PR builds
  - `v0.<pr>.0` for merged/tagged release builds
- Deployments should pin by digest where feasible.

### Helm OCI charts

- Chart reference: `oci://<nexus>/oci-helm-homelab-hosted/<chart-name>`
- `version`: semver release tag (`v0.<pr>.0` mapped to chart semver)
- `appVersion`: source commit (`sha-<git_sha7>`)

### Raw bundles

- Path pattern: `raw-ci-hosted/<project>/<artifact_type>/<version>/`
- Filename pattern: `<name>_<version>_<sha7>.<ext>`

## CI Identity and Secrets

Store these credentials in 1Password and inject via GitHub Actions secrets:

- `NEXUS_URL`
- `NEXUS_CI_USERNAME`
- `NEXUS_CI_PASSWORD`

Use a dedicated Nexus CI account with least privilege per repository type.

## Implementation Order

1. Create repositories listed above in Nexus.
2. Create CI service account and scoped roles.
3. Add GitHub Actions secrets from 1Password.
4. Add build/publish jobs in `.github/workflows/ci-testing.yml` (or a dedicated release workflow).
5. Record artifact outputs in PR summary for traceability.
