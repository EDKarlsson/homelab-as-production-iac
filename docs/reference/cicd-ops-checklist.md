---
title: CI/CD Ops Checklist (Session Handoff)
description: Save-for-tomorrow checklist for CI/CD setup, validation, and operational caveats
published: true
date: 2026-02-19
tags:
  - cicd
  - operations
  - handoff
  - nexus
  - gitops
---

# CI/CD Ops Checklist (Session Handoff)

As of **February 19, 2026**, the most useful things to save for tomorrow are:

1. A one-time setup checklist for Nexus auth in GitHub:
- Secrets: `NEXUS_URL`, `NEXUS_CI_USERNAME`, `NEXUS_CI_PASSWORD`
- Optional repo variable: `NEXUS_RAW_REPO`
- Optional repo variable: `ENABLE_AUTO_SMOKE=true` (if you want smoke checks on `main` pushes)

2. Exact Nexus-side provisioning details:
- Which repos were created
- CI service account name
- Role/permission mapping per repo type

3. First-run validation notes:
- `workflow_dispatch` test run IDs
- Whether `Publish CI Artifacts to Nexus` succeeded
- Artifact URL path used in Nexus

4. Release workflow usage examples:
- 2-3 known-good inputs for `.github/workflows/release-gitops-update.yml`
- Example rollback invocation using the same workflow

5. A short “known caveats” note:
- Local `yq` snap limitation seen in this environment (GitHub runner uses standalone `yq` binary and is fine)

Most of the strategy is already captured in:

- `docs/CICD-PLAN.md`
- `docs/guides/cicd-artifact-strategy.md`
- `docs/guides/gitops-promotion-and-rollback.md`
- `docs/guides/ci-cd-testing-workflow.md`
