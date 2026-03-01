# Start Task

$ARGUMENTS

## 1. Parse task and determine branch

- Analyze $ARGUMENTS for the task type and scope
- If $ARGUMENTS references a plan file (e.g., a path in `docs/handoffs/` or `docs/`), read it and use it as the implementation plan
- Determine the conventional commit prefix from the task description:
  - New feature → `feat/`
  - Bug fix → `fix/`
  - Upgrade, dependency, maintenance → `chore/`
  - Documentation only → `docs/`
- Generate a kebab-case branch name: `<prefix>/<short-description>-<YYYYMMDD>`
  - Example: `chore/nexus-upgrade-20260219`, `feat/comfyui-proxmox-vm-20260219`

## 2. Sync main and create worktree

Ensure the primary working directory is clean and up to date:

```bash
git checkout main
git pull origin main
```

Create a git worktree in `/tmp/` following the existing convention:

```bash
git worktree add /tmp/homelab-iac-<short-name> -b <branch-name>
```

Where `<short-name>` is a concise identifier (e.g., `nexus-upgrade`, `comfyui`, `eso-bump`).

**CRITICAL**: From this point forward, ALL file operations (Read, Edit, Write, Glob, Grep) MUST use absolute paths rooted at the worktree directory `/tmp/homelab-iac-<short-name>/`. The primary working directory stays on main — do not modify files there.

Store the worktree path for reference:
```
WORKTREE=/tmp/homelab-iac-<short-name>
```

## 3. Verify worktree

- Confirm the worktree was created: `git worktree list`
- Confirm the branch is checked out: `git -C $WORKTREE branch --show-current`
- Read the CLAUDE.md from the worktree to confirm file access works

## 4. Create task list and begin work

- If a plan was loaded from $ARGUMENTS, create tasks from its phases/steps
- If no plan exists, enter plan mode to design the approach
- Initialize branch task plan + lock scope before mutating homelab commands:

```bash
git -C $WORKTREE rev-parse --abbrev-ref HEAD
git -C $WORKTREE scripts/coord/task-plan-init.sh --summary "<one-line task summary>" --services "<svc1,svc2>"
git -C $WORKTREE scripts/coord/task-plan-validate.sh
git -C $WORKTREE scripts/coord/lock-acquire.sh --ttl-minutes 240
```

- Begin implementation — all file modifications happen in the worktree
- Run mutating commands through guard preflight so lock files are checked every invocation:

```bash
git -C $WORKTREE scripts/coord/guard.sh terraform plan
git -C $WORKTREE scripts/coord/guard.sh terraform apply
git -C $WORKTREE scripts/coord/guard.sh kubectl apply -f <file>
git -C $WORKTREE scripts/coord/guard.sh flux reconcile kustomization <name>
```

## 5. Merge cycle (when verification against live cluster is needed)

For GitOps changes that require Flux reconciliation to verify:

1. **Commit and push** from the worktree:
   ```bash
   git -C $WORKTREE add <files>
   git -C $WORKTREE commit -m "<message>"
   git -C $WORKTREE push -u origin <branch-name>
   ```
2. **Create PR**: `gh pr create` (from worktree directory)
3. **Wait for CI**: `gh pr checks <number>` / `gh run watch <run-id>`
4. **Merge**: `gh pr merge <number> --merge --admin` (if CI passes)
   - Do NOT use `--delete-branch` during intermediate merges — the worktree still needs the branch
5. **Update main** in primary worktree: `git -C /home/homelab-admin/git/valhalla/homelab-iac pull`
6. **Rebase worktree** on updated main: `git -C $WORKTREE rebase main`
7. **Verify** via kubectl and proceed to next phase

For the final merge (no more changes needed), use `--delete-branch` and clean up the worktree in the finalize step.

## 6. kubectl access

Always use the Tailscale API proxy context for cluster access:
```bash
KUBECONFIG=~/.kube/config-homelab kubectl --context=tailscale-operator.homelab.ts.net <command>
```

## Notes

- The primary repo (`/home/homelab-admin/git/valhalla/homelab-iac`) stays on `main` — it's the clean reference and what Flux tracks
- Multiple worktrees can coexist for parallel tasks (each with its own branch)
- Release coordination locks before ending the session: `git -C $WORKTREE scripts/coord/lock-release.sh --all`
- If the session ends before finalize, the worktree persists in `/tmp/` and can be resumed
- Worktree cleanup happens during `/finalize` or manually via `git worktree remove`
