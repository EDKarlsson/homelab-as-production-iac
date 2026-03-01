---
title: MCP Kubernetes Deployment Strategy
description: Analysis and rollout plan for centralizing MCP servers in Kubernetes, including automatic agent configuration
published: true
date: 2026-02-19
tags:
  - mcp
  - kubernetes
  - ai
  - flux
  - automation
---

Strategy for reducing duplicate local MCP processes by centralizing the right MCP servers in Kubernetes, while keeping local-only servers local.

## Objective

1. Run shared infrastructure MCP servers once in the cluster instead of once per AI agent process.
2. Keep local-context MCP servers (filesystem, memory, etc.) local to each agent.
3. Standardize agent onboarding with generated MCP config files.

## MCP Inventory Found in This Repo

Sources used:

- `docs/reference/postgresql-ha.md`
- `docs/analysis/overnight-audit-2026-02-18.md`
- `.devcontainer/mcp/cline_mcp_settings.op.json`
- `.vscode/homelab-iac.op.code-workspace`
- `configs/mcp/drawio-mcp.example.json`
- `.mcp.json` (active configuration, updated 2026-02-26)

| MCP server | Status | Typical dependency |
|---|---|---|
| kubernetes | Active (local `kubernetes-mcp-server`) | kubeconfig / K8s API |
| flux | Active (local `/home/homelab-admin/.local/bin/flux-operator-mcp`) | Flux CRs in cluster |
| terraform | Active (local `/home/homelab-admin/go/bin/terraform-mcp-server`) | local repo context + registry |
| postgres | Active (local `@modelcontextprotocol/server-postgres`) | PostgreSQL VIP `10.0.0.44` |
| prometheus | Active (local `prometheus-mcp`) | Prometheus endpoint |
| github | Active (HTTP proxy via `api.githubcopilot.com`) | GitHub remote API |
| context7 | Active (local `@upstash/context7-mcp`) | Upstash cloud API |
| drawio | Active (local `npx @drawio/mcp`) | local filesystem `.drawio` files |
| gitlab | Active (local `@modelcontextprotocol/server-gitlab`) | GitLab API |
| filesystem | devcontainer only | local filesystem |
| memory | devcontainer only | local process state |
| sequentialthinking | devcontainer only | local process state |
| todoist | devcontainer only | Todoist cloud API + per-user token |
| task-master-ai | VS Code workspace only | local repo/task context |
| slack | Not deployed | Slack API |
| huggingface | Not deployed | Hugging Face API |

## Deployment Decision Matrix

| MCP server | Deploy in K8s? | Decision |
|---|---|---|
| kubernetes | Yes | High-value shared ops server; use in-cluster ServiceAccount with read-only RBAC by default |
| flux | Yes | Cluster-local data source; centralize and keep read-only by default |
| prometheus | Yes | Already cluster-hosted target; central server avoids duplicate local wrappers |
| postgres | Yes | Existing `mcp_readonly` model is a good fit for central shared service |
| drawio | No (local npx) | Running locally via `npx @drawio/mcp` is sufficient; self-hosted `/export` endpoint requires headless Chrome and returns 500 without it -- MCP approach avoids this entirely |
| terraform | No | Strong local-repo coupling; centralizing loses local working tree context |
| filesystem | No | Must remain local to the agent machine/workspace |
| memory | No | Per-agent state by design |
| sequentialthinking | No | Per-agent reasoning helper; no shared infra value |
| task-master-ai | No | Project-local workflow/state; best kept local |
| github | No | Already remote HTTP service; little gain from self-hosting |
| context7 | No | Cloud API wrapper; little gain from self-hosting |
| todoist | No | Per-user token and personal scope; not a shared infra server |
| slack | No (for now) | API integration is possible but lower priority than ops MCPs |
| huggingface | No (for now) | Future ML use case; not an immediate homelab ops target |

## Recommended First Wave (Deploy Now)

Deploy these 4 first, then optionally Draw.io:

1. `kubernetes`
2. `flux`
3. `prometheus`
4. `postgres`
5. `drawio` (optional)

Why this set:

- These are directly tied to homelab operations and cluster observability.
- They remove the most duplicate per-agent processes.
- They can be made read-only and scoped via RBAC/DB privileges.

## Kubernetes Placement and GitOps Pattern

Place MCP workloads under `kubernetes/apps/` (not `platform/controllers/`).

Rationale:

- MCP servers are operator tooling, not platform prerequisites.
- A failure should not block controller/bootstrap reconciliation.
- This follows the existing Flux ordering (`platform-controllers -> platform-configs -> apps`).

Recommended layout:

```text
kubernetes/apps/mcp-kubernetes/
kubernetes/apps/mcp-flux/
kubernetes/apps/mcp-prometheus/
kubernetes/apps/mcp-postgres/
kubernetes/apps/mcp-drawio/        # optional
```

Each app follows existing patterns:

- `namespace.yaml` (with tenant label)
- `external-secret.yaml` (when credentials are needed)
- `deployment.yaml`
- `service.yaml`
- `tailscale-ingress.yaml` (for remote agents)
- `kustomization.yaml`

## Security and Guardrails

1. Default to read-only behavior:
   - K8s/Flux MCP RBAC read-only cluster role.
   - PostgreSQL uses `mcp_readonly`.
2. Use `ExternalSecret` + `ClusterSecretStore` for all tokens/credentials.
3. Add NetworkPolicies:
   - Restrict egress to required destinations only (K8s API, Prometheus service, PG VIP).
4. Expose via Tailscale ingress only (no public ingress).
5. Keep write-capable tooling opt-in and separated from daily read-only endpoints.

## Automatic Agent Configuration (Recommended Design)

Use generated local MCP config from tracked templates, resolved with 1Password at generation time.

### Files

```text
configs/mcp/profiles/homelab-shared.mcp.op.json
configs/mcp/profiles/local-tools.mcp.op.json
configs/mcp/catalog/servers.json
scripts/mcp/generate-config.sh
```

### Workflow

1. `servers.json` is the single source of endpoint URLs and server names.
2. `homelab-shared.mcp.op.json` references those endpoints and `op://` secrets.
3. `scripts/mcp/generate-config.sh` renders `.mcp.json` (or client-specific outputs) by:
   - loading profile + catalog
   - running `op inject`
   - validating with `jq`
4. Agents load generated config automatically at startup.

Example usage:

```bash
op run --env-file configs/final.env -- \
  bash scripts/mcp/generate-config.sh --profile homelab-shared --out .mcp.json
```

This preserves your current 1Password-driven secret model and avoids committing local credentials.

## Rollout Plan

1. Phase 1: Deploy `mcp-prometheus` and `mcp-postgres` (lowest RBAC risk).
2. Phase 2: Deploy `mcp-kubernetes` and `mcp-flux` with read-only RBAC.
3. Phase 3: Add generated config pipeline (`configs/mcp/profiles` + `scripts/mcp/generate-config.sh`).
4. Phase 4: Evaluate Slack/HuggingFace only if usage justifies. Draw.io stays local (npx).

## Success Criteria

1. Agents use shared cluster MCP endpoints for K8s/Flux/Prometheus/Postgres.
2. Local MCP processes are limited to local-context tools only.
3. New agent bootstrap requires one command to generate working MCP config.
4. No secrets are committed; all credentials continue to flow from 1Password.

## Multi-Agent Future Goal

The long-term goal is to run all shared MCP servers as K8s Deployments in the cluster so that multiple AI agents (Claude Code, Codex, Gemini, GitHub Copilot) can share a single set of infrastructure MCP endpoints. This eliminates duplicate local `npx` processes per-agent and enables a centralized agent-control-plane pattern. Each server would be exposed via a Tailscale ingress so remote agents can reach it without LAN access. Local MCP servers (terraform, drawio, filesystem) remain per-agent by design.
