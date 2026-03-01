# CI/CD Incident Triage Runbook

Triage steps for CI/CD and GitOps alerts. Each section maps to a specific Prometheus alert rule or Flux notification event.

---

## GitHub Actions Alerts

### GitHubWorkflowFailed

**Severity**: warning | **For**: 5m

A GitHub Actions workflow completed with a failure status.

**Triage steps**:

1. Check the exporter metric for which workflow failed:
   ```promql
   github_workflow_run_status{repo="homelab-admin/homelab-iac"} == 0
   ```
2. Open the workflow run on GitHub:
   - `https://github.com/homelab-admin/homelab-iac/actions`
   - Filter by the workflow name and run number from the alert labels.
3. Review the failed job logs for the root cause.
4. Common causes:
   - **Linting/validation failure**: Fix the code and re-push.
   - **Timeout**: Check if the runner was overwhelmed or the job has a new slow step.
   - **Secret expired**: Rotate the affected secret in 1Password and re-sync.
   - **Flaky test**: Re-run the workflow. If it passes, investigate intermittent issues.
5. If the failure is in CI checks for a PR, the branch protection gate will block merge — the author should be notified.

### GitHubWorkflowStuck

**Severity**: warning | **For**: 30m

A workflow has been in "In Progress" state for more than 30 minutes.

**Triage steps**:

1. Verify the workflow is genuinely stuck (not just a long-running job):
   ```promql
   github_workflow_run_status == 3
   ```
2. Check the GitHub Actions UI for the specific run — look for jobs waiting on a runner or stuck steps.
3. Common causes:
   - **Self-hosted runner offline**: Runner can't pick up the job. See `GitHubSelfHostedRunnerOffline` below.
   - **Waiting for approval**: Environment protection rules may require manual approval.
   - **Resource exhaustion**: The runner may be out of disk or memory.
4. Cancel the stuck run from the GitHub Actions UI if it can't recover.
5. Re-trigger the workflow after fixing the underlying issue.

### GitHubSelfHostedRunnerOffline

**Severity**: warning | **For**: 10m

A self-hosted GitHub Actions runner has been offline for more than 10 minutes.

**Triage steps**:

1. Identify which runner is offline:
   ```promql
   github_runner_status == 0
   ```
2. Check the runner host:
   - SSH into the runner machine.
   - Check `systemctl status actions.runner.*` (systemd service) or the runner process.
   - Review `/home/<runner-user>/_diag/Runner_*.log` for errors.
3. Common causes:
   - **Node rebooted**: Runner service didn't auto-start. Enable the systemd service.
   - **Token expired**: Re-register the runner with a fresh token from GitHub Settings > Actions > Runners.
   - **Disk full**: Clean up old work directories under `_work/`.
   - **Network issue**: Verify outbound HTTPS to `github.com` and `*.actions.githubusercontent.com`.
4. Restart the runner service and verify it reconnects.

---

## Flux Deployment Health Alerts

### FluxReconciliationFailed

**Severity**: warning | **For**: 15m

A Flux resource has been in a failed (not ready) state for 15 minutes. This is the existing base alert.

**Triage steps**:

1. Identify the failing resource:
   ```bash
   flux get all -A --status-selector ready=false
   ```
2. Get detailed error message:
   ```bash
   flux get helmrelease -A  # or kustomization, gitrepository, etc.
   kubectl describe <kind> <name> -n <namespace>
   ```
3. Common causes:
   - **Helm chart fetch failed**: HelmRepository may be down or chart version doesn't exist.
   - **Kustomize build failed**: Invalid YAML, missing resources, or patch errors.
   - **Values error**: Incorrect Helm values causing template rendering failure.
   - **Dependency not ready**: Check `spec.dependsOn` — a prerequisite may still be failing.
4. Fix the manifest in Git → push → Flux will auto-reconcile.
5. Force immediate reconciliation:
   ```bash
   flux reconcile helmrelease <name> -n <namespace>
   ```

### FluxReconciliationErrorRate

**Severity**: warning | **For**: 15m

More than 25% of reconciliation attempts for a specific resource are failing over a 15-minute window. This catches intermittent failures that recover between checks.

**Triage steps**:

1. Check the error rate metric:
   ```promql
   sum by (exported_namespace, name) (
     rate(gotk_reconcile_condition{type="Ready", status="False"}[15m])
   ) / sum by (exported_namespace, name) (
     rate(gotk_reconcile_condition{type="Ready"}[15m])
   )
   ```
2. This typically indicates a flapping resource — succeeds sometimes, fails others.
3. Common causes:
   - **Transient network issues**: HelmRepository or GitRepository fetch intermittently timing out.
   - **Resource contention**: Another controller modifying the same resources.
   - **Rate limiting**: Helm chart repository or container registry rate limiting.
4. Check Flux controller logs:
   ```bash
   kubectl logs -n flux-system deploy/helm-controller --tail=100
   kubectl logs -n flux-system deploy/source-controller --tail=100
   ```

### FluxSourceRevisionStale

**Severity**: info | **For**: 30m

A GitRepository source has not received a new revision in over 6 hours.

**Triage steps**:

1. This is typically informational — no commits have been pushed in 6 hours.
2. Verify the source is still polling correctly:
   ```bash
   flux get sources git -A
   ```
3. If the source shows errors, the fetch mechanism may be broken:
   - Check SSH key or PAT token expiry.
   - Verify GitHub API accessibility from the cluster.
4. Only investigate if you expected recent commits that aren't being picked up.

### FluxHelmReleaseSuspendedLong

**Severity**: info | **For**: 72h

A HelmRelease has been suspended for more than 72 hours. This is informational — suspension is sometimes intentional.

**Triage steps**:

1. List suspended releases:
   ```bash
   flux get helmrelease -A --status-selector suspended=true
   ```
2. Check if the suspension was intentional (e.g., Plex is suspended pending NFS permission fix).
3. If the release should be active, resume it:
   ```bash
   flux resume helmrelease <name> -n <namespace>
   ```
4. Known intentionally suspended releases:
   - `plex` (media namespace) — suspended pending NAS NFS share permission update for new VM IPs.

---

## Flux Notification Events (Slack)

These are real-time Slack messages from Flux notification-controller (not Prometheus alerts). They fire immediately on error events — no `for` duration.

### Kustomization/HelmRelease Error

**What you'll see in Slack**: A message from the Flux notification provider with the error event details.

**Triage steps**:

1. The Slack message contains the resource kind, name, namespace, and error message.
2. Follow the same triage steps as `FluxReconciliationFailed` above.
3. Key difference: Slack notifications fire immediately, while the Prometheus alert has a 15-minute `for` duration. Use the Slack notification for early awareness, the Prometheus alert for confirmed persistent failures.

### Source Fetch Error

**What you'll see in Slack**: GitRepository or HelmRepository/HelmChart error event.

**Triage steps**:

1. Check if the source URL is reachable from the cluster:
   ```bash
   kubectl exec -n flux-system deploy/source-controller -- wget -q -O /dev/null <url>
   ```
2. For GitRepository: verify the SSH deploy key or GitHub PAT is still valid.
3. For HelmRepository: verify the chart repository is up and the URL is correct.
4. Force retry:
   ```bash
   flux reconcile source git <name>
   flux reconcile source helm <name>
   ```

---

## Escalation

1. **Self-service**: Most CI/CD issues can be resolved by fixing code and re-pushing.
2. **Infrastructure**: If runners, Flux controllers, or the monitoring stack itself is down, check node health first (`NodeNotReady`, `PVENodeDown` alerts).
3. **Secrets**: If secrets-related failures cascade, check 1Password Connect health:
   ```bash
   kubectl get externalsecrets -A
   curl -s http://10.0.0.72:8080/health
   ```

---

## Dashboards

| Dashboard | URL | Shows |
|-----------|-----|-------|
| CI/CD Pipeline | Grafana > CI/CD Pipeline | Workflow status, duration, runner health |
| GitOps Health | Grafana > GitOps Health | Flux resources, reconciliation rates, sources |
| Flux Control Plane | Grafana > Flux Control Plane | Controller metrics, API requests, Helm stats |
| Flux Cluster Stats | Grafana > Flux Cluster Stats | Reconciliation status by kind |
