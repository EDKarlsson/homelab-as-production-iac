# Homelab IaC - CI/CD Plan

Status: **Planning started (2026-02-19).**
Baseline CI testing workflow is merged (PR #89). This plan tracks the next implementation phases for a full CI/CD pipeline that uses existing homelab services.

---

## Goals

1. Keep infrastructure changes safe with automated validation gates.
2. Build and publish reusable artifacts through homelab services.
3. Deploy changes through GitOps with controlled promotion.
4. Add observability, rollback strategy, and operational runbooks.

## Target Service Integration

- **GitHub Actions**: source-triggered CI checks and orchestration.
- **TeamCity**: optional heavy/self-hosted build and integration workloads.
- **Nexus**: artifact and image caching/hosting.
- **FluxCD**: deployment reconciliation from `main`.
- **1Password + ESO**: secrets for CI/CD credentials.
- **Prometheus/Grafana + Alertmanager**: pipeline and deployment health monitoring.

## Phase 1 - CI Baseline Hardening

- [x] Add PR workflow for Terraform/Ansible/K8s/script checks.
- [x] Enforce branch protection required checks for `main` (`CI Summary`, strict up-to-date checks).
- [x] Add status badges and quick-fail troubleshooting section to README.
- [x] Add policy gates for pinned versions and risky patterns (`ci/policy-check.sh` expansion).

## Phase 2 - Artifact Pipeline

- [x] Define artifact strategy (container images, Helm/chart assets, script bundles).
- [x] Configure Nexus repositories and naming conventions.
- [x] Add CI jobs to build/version/push artifacts to Nexus.
- [x] Add provenance metadata (commit SHA, build timestamp, source branch).

## Phase 3 - Continuous Delivery Flow

- [x] Define environment promotion model (single-cluster GitOps promotion: PR -> main -> Flux).
- [x] Add Flux-compatible release manifest update workflow (GitOps-first).
- [x] Add deployment verification gates (CI Summary required + optional auto-smoke via `ENABLE_AUTO_SMOKE`).
- [x] Document rollback playbooks for failed releases.

## Phase 4 - Observability and Operations

- [x] Export CI/CD metrics to Prometheus (workflow failures, deployment latency, drift).
- [x] Add alert rules for failing pipeline stages and stale deployments.
- [x] Create dashboards for CI, CD, and GitOps reconciliation health.
- [x] Add operational runbook for incident triage.

## Phase 5 - Self-Hosted CI/CD Parity (Tailscale)

- [ ] Implement a comparable CI/CD pipeline using self-hosted GitLab CI + TeamCity with Nexus as the artifact backbone, using Tailscale-hosted endpoints as the primary integration path.

## PLAN File Workflow (Canonical Tracking)

Use `docs/*PLAN*.md` as the single source of truth for planning:

1. Add new goals/tasks as unchecked checklist items in the relevant PLAN file.
2. Link concrete implementation PRs/commits back to those checklist items.
3. Update status in the PLAN file immediately after merge.
4. Mirror major milestone progress in `docs/CHANGELOG.md`.
5. Keep cross-plan dependencies synced between `docs/PROJECT-PLAN.md` and this file.

## Next Actions

1. Create Nexus CI service account and map credentials into GitHub secrets (`NEXUS_URL`, `NEXUS_CI_USERNAME`, `NEXUS_CI_PASSWORD`).
2. Run a manual `workflow_dispatch` to validate raw artifact publish end-to-end.
3. Start Phase 4: CI/CD observability (metrics export, alerts, dashboards, and runbook).
4. Define implementation plan for Phase 5 GitLab/TeamCity/Nexus pipeline parity over Tailscale.
