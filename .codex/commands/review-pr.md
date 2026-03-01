Review a pull request and publish a formal PR review with actionable feedback.

$ARGUMENTS

## 1. Resolve target PR

- If `$ARGUMENTS` includes a PR number, use it.
- If `$ARGUMENTS` is empty, infer PR from current branch:
  - `gh pr view --json number --jq '.number'`
- If no PR can be resolved, stop and report the error.

## 2. Gather review context (prefer `gh` commands)

- Metadata:
  - `gh pr view <number> --json number,title,author,headRefName,baseRefName,state,isDraft,mergeStateStatus,reviewDecision,url,changedFiles,additions,deletions`
- File list:
  - `gh pr diff <number> --name-only`
- Full diff:
  - `gh pr diff <number> > /tmp/pr-<number>.diff`
- CI status:
  - `gh pr checks <number>`
- Optional failed logs when checks fail:
  - `gh run view <run-id> --log-failed`

After metadata is loaded, explicitly gate review depth:
- If `isDraft=true`, call it out in the summary and focus on early/high-impact feedback.
- If `mergeStateStatus` is `DIRTY`/`BEHIND`/otherwise not merge-ready, include that as a finding and recommend rebase/conflict resolution first.

## 3. Perform review

Use a code-review mindset first: bugs, risks, regressions, and missing tests.

For each issue, capture:
- Severity: `High`, `Medium`, or `Low`
- Path + line reference (example: `scripts/coord/guard.sh:102`)
- Why this is a problem (behavioral impact)
- Concrete fix suggestion

Also include:
- Improvements that are not blockers
- What should be documented and saved in-repo (guides, runbooks, gotchas, changelog, project plan, version matrix)

## 4. Documentation and knowledge-capture checks

If relevant files changed, explicitly verify whether docs should also be updated:

- Infra/app version or image/chart changes:
  - `docs/reference/version-matrix.md`
- New behavior, workflow, or operational process:
  - `docs/guides/` and `docs/reference/CONTRIBUTING.md`
- Notable fix/incident/root-cause:
  - `docs/reference/technical-gotchas.md` and/or troubleshooting docs
- Significant session-level change:
  - `docs/CHANGELOG.md`

Call out missing docs updates in review feedback.

## 5. Publish PR review decision

Build a review body with this structure:

1. `Findings` (ordered by severity)
2. `Suggestions for improvement`
3. `Documentation to add/update`
4. `CI/Test status`
5. `Decision`

Decision rule:
- If **no issues found**, submit approval:
  - `gh pr review <number> --approve --body-file <review-body-file>`
- If **any issue found**, submit request-changes:
  - `gh pr review <number> --request-changes --body-file <review-body-file>`

If GitHub blocks request-changes (for example, reviewing your own PR), post:
- `gh pr review <number> --comment --body-file <review-body-file>`
- Clearly state in the comment: "Would request changes, but GitHub does not allow requesting changes on own PR."

## 6. Return summary

After posting review, report:
- PR number and URL
- Decision posted (`approve`, `request-changes`, or `comment` fallback)
- Count of findings by severity
- Top 1-3 highest-impact fixes

## 7. Sync note

- Keep this file and `.claude/commands/review-pr.md` functionally equivalent unless there is a deliberate, documented divergence.
