Clean up stale Git branches whose pull requests have been merged or closed.

## Steps

### 1. Discover stale branches

Run `gh pr list --state merged` and `gh pr list --state closed` to find all branches with completed PRs. Also check for remote branches that have NO associated PR (orphan branches). Cross-reference with `git branch -r` to confirm they still exist on the remote.

Categorize each branch:
- **Merged** — PR was merged into main
- **Closed** — PR was closed without merging
- **Orphan** — Remote branch exists but has no PR

Exclude `main` and the current branch from the list.

### 2. Present the branch list

Display a markdown checkbox list grouped by category, with PR number, branch name, and title. Format:

```
### Merged PR branches
- [ ] 1. `feat/example-branch` — PR #42: Add example feature (merged 2026-02-15)
- [ ] 2. `fix/bug-branch` — PR #43: Fix critical bug (merged 2026-02-16)

### Closed PR branches (not merged)
- [ ] 3. `feat/abandoned` — PR #44: Abandoned feature (closed 2026-02-14)

### Orphan branches (no PR)
- [ ] 4. `task/random-branch` — no associated PR
```

### 3. Ask the user which branches to delete

Ask the user to specify which branches to delete by number (e.g., "1, 2, 4" or "all" or "all merged"). Wait for their response before proceeding.

### 4. Delete selected branches

For each selected branch:

1. Delete the remote branch: `git push origin --delete <branch-name>`
2. Delete the local branch if it exists: `git branch -d <branch-name>` (use `-D` only if `-d` fails and the user confirms)
3. Prune stale remote-tracking references: `git remote prune origin`

Report results for each deletion (success or failure with reason).

### 5. Summary

Show a final summary of what was deleted and what remains.
