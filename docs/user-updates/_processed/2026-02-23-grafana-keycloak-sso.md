# TODO: Grafana Keycloak SSO

**Date**: 2026-02-23
**Status**: Done — merged PR #146, verified 2026-02-24

## Problem

Grafana shows username/password login instead of Keycloak SSO.
The Grafana ingress has oauth2-proxy annotations but Grafana itself has no OAuth config.

## Plan: Native Grafana OAuth (`auth.generic_oauth`)

Use Grafana's built-in OAuth support to talk to Keycloak directly.
**All URLs use Tailscale domain exclusively** (`grafana.homelab.ts.net`).
The Tailscale ingress already exists in `platform/configs/tailscale-ingress.yaml`.
No nip.io URLs — Tailscale is the DNS/access layer for everything.

---

## Step 1 — Create Grafana client in Keycloak

Go to `https://keycloak.homelab.ts.net` → **homelab** realm → **Clients** → Create:

| Field | Value |
|---|---|
| Client ID | `grafana` |
| Client type | OpenID Connect |
| Client authentication | ON (confidential) |
| Authorization | OFF |

**Settings tab:**
- Valid redirect URIs: `https://grafana.homelab.ts.net/login/generic_oauth`
- Web origins: `https://grafana.homelab.ts.net`

**Credentials tab** → copy the client secret.

---

## Step 2 — Store in 1Password

```bash
op item create --vault Homelab --category login \
  --title "grafana-keycloak-oidc" \
  'GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana' \
  'GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=<paste-from-keycloak>'
```

Keys use `GF_` prefix so Grafana reads them automatically from env vars.

---

## Step 3 — Create ExternalSecret

New file: `kubernetes/platform/monitoring/configs/grafana-keycloak-oidc-external-secret.yaml`

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-keycloak-oidc
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: grafana-keycloak-oidc
    creationPolicy: Owner
  data:
    - secretKey: GF_AUTH_GENERIC_OAUTH_CLIENT_ID
      remoteRef:
        key: grafana-keycloak-oidc
        property: GF_AUTH_GENERIC_OAUTH_CLIENT_ID
    - secretKey: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
      remoteRef:
        key: grafana-keycloak-oidc
        property: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
```

Add to `kubernetes/platform/monitoring/configs/kustomization.yaml`:
```yaml
resources:
  - ...
  - grafana-keycloak-oidc-external-secret.yaml
```

---

## Step 4 — Update HelmRelease

File: `kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml`

### 4a. Remove oauth2-proxy ingress annotations from `grafana.ingress`

Delete these three annotations (they cause double-redirect with native OAuth):
```yaml
# REMOVE:
nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy..."
nginx.ingress.kubernetes.io/auth-signin: "https://oauth2-proxy..."
nginx.ingress.kubernetes.io/auth-response-headers: "..."
```

### 4b. Add to the `grafana:` values block

```yaml
grafana:
  envFromSecret: "grafana-keycloak-oidc"   # GF_AUTH_* env vars from Secret

  extraVolumes:
    - name: homelab-ca
      configMap:
        name: homelab-ca-cert
  extraVolumeMounts:
    - name: homelab-ca
      mountPath: /etc/ssl/homelab
      readOnly: true

  grafana.ini:
    server:
      root_url: "https://grafana.homelab.ts.net"
    auth.generic_oauth:
      enabled: true
      name: Keycloak
      allow_sign_up: true
      auto_login: true
      scopes: "openid profile email"
      auth_url: "https://keycloak.homelab.ts.net/auth/realms/homelab/protocol/openid-connect/auth"
      token_url: "https://keycloak.homelab.ts.net/auth/realms/homelab/protocol/openid-connect/token"
      api_url: "https://keycloak.homelab.ts.net/auth/realms/homelab/protocol/openid-connect/userinfo"
      role_attribute_path: "'Admin'"
      tls_client_ca: /etc/ssl/homelab/ca.crt
```

> **Note on `tls_client_ca`**: Grafana pods resolve `keycloak.homelab.ts.net` via
> CoreDNS override to 10.0.0.201, where nginx serves a homelab CA cert. This CA
> mount is the same pattern used by oauth2-proxy.

> **`role_attribute_path: "'Admin'"`**: Gives all authenticated Keycloak users Admin
> in Grafana. Fine for single-user homelab. For role-based: use JMESPath against
> groups claim, e.g. `contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'`.

---

## Files to create/modify

| File | Change |
|---|---|
| `kubernetes/platform/monitoring/configs/grafana-keycloak-oidc-external-secret.yaml` | Create |
| `kubernetes/platform/monitoring/configs/kustomization.yaml` | Add new ExternalSecret |
| `kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml` | Remove oauth2-proxy annotations, add OAuth config |

## Verification

After deploying:
1. Hit `https://grafana.homelab.ts.net` → should redirect to Keycloak immediately
2. Log in → should land in Grafana as Admin
3. Check `Admin → Profile` — user should show Keycloak email/username

---

## Related: nip.io cleanup (broader, lower priority)

Decided against setting up dedicated DNS infrastructure (Pi-hole, Technitium, etc.) —
Tailscale already IS the DNS layer for all connected devices. Not worth the overhead.

Going forward:
- New apps: Tailscale ingress only, no nip.io
- Existing nip.io ingresses: leave in place (harmless), clean up opportunistically
- oauth2-proxy: check what apps still use it — if Grafana is the only protected app,
  consider retiring oauth2-proxy entirely once native OAuth is in place for Grafana
