Finalize the current work session. Run all steps in order:

## 1. Knowledge capture

- Run the `knowledge-capture` skill as a background subagent to sync technical findings from memory files to `docs/reference/`.
- This ensures any new gotchas, research, or troubleshooting knowledge from this session is captured in Wiki.js-ready docs before the session ends.
- Wait for the subagent to finish before proceeding to step 2.

## 2. Document changes

- Review all files modified in this session (use `git diff` against the base branch or last commit).
- Save a summary of changes where appropriate (session notes, memory files, guide updates).
- Update any guides or documentation affected by the changes.

## 3. Changelog

- Create or append to a changelog summarizing what changed, why, and any notable decisions.
- Include the list of modified files and a brief description of each change.

## 4. Commit and push

- If not already on a feature branch, create one with an appropriate name (e.g., `feat/short-description` or `fix/short-description`).
- Stage and commit all changes with a clear commit message.
- Push the branch to origin.

**Note:** Going forward, checkout a new branch *before* starting work. This step handles the one-time case where work was done on main.

## 5. Pull request and review

- Create a pull request against `main` using `gh pr create`.
- Review the PR diff and provide clear, concise feedback:
  - Highlight any changes that may need additional documentation.
  - Flag possible issues or risks down the line.
  - Note any follow-up tasks that should be tracked.

## 6. Merge, update main, and clean up

After creating the PR, merge it and clean up the branch automatically:

- Review the PR for any issues: `gh pr diff <number>`
- If no issues found, merge the PR: `gh pr merge <number> --merge --delete-branch`
- Switch to main and pull: `git checkout main && git pull`
- Delete the local feature branch: `git branch -d <branch-name>`
- Prune stale remote tracking refs: `git remote prune origin`
- If there are issues, flag them to the user instead of merging.

## 7. Tag release

After merging, create a semver tag based on the PR number:

- Get the PR number from the merge step (e.g., `#57`).
- Tag format: `v0.<PR#>.0` (pre-1.0 convention — PR number is the minor version).
- Create an annotated tag: `git tag -a v0.<PR#>.0 -m "v0.<PR#>.0: <one-line summary>"`
- Push the tag: `git push origin v0.<PR#>.0`
- Patch versions (`v0.<PR#>.1`) are for hotfixes on the same PR's work.

## 8. Version check

After tagging, run a version audit and update `docs/reference/version-matrix.md`:

1. **Check for version changes this session:**
   - Compare the git diff (all commits in the merged PR) for any image tag or chart version changes.
   - For each version change found, add a row to the **Version Change Log** table in the matrix:
     - Date, App, From version, To version, Homelab Tag (the tag just created), Reason (why the upgrade was done).

2. **Spot-check for newer versions:**
   - For any app that was modified this session, check if a newer version is available than what was just deployed.
   - For apps NOT modified, only flag if the matrix shows them as High priority in the Upgrade Priority section.
   - Use web search to check for critical CVEs or security advisories for outdated components.
   - Update the **Latest Available** column and **Status** for any apps where the latest version has changed since the last audit.

3. **Update the matrix metadata:**
   - Update the `Last audited` date at the top of the document.
   - Update the **Summary Statistics** counts if any statuses changed.
   - Commit the version matrix update as part of the finalize branch (before the PR), or as an amendment if the matrix changes are discovered after the main commit.
