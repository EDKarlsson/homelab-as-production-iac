Review and triage user update files from `docs/user-updates/`.

## 1. Scan for pending updates

- List all files in `docs/user-updates/` (exclude `TEMPLATE.md` and `_processed/`).
- If no files found, report "No pending updates" and stop.
- If multiple files found, process each one individually (don't batch).

## 2. Analyze each file

For each update file, read it and perform this analysis:

### 2a. Parse and understand
- Identify each distinct idea, request, or change in the file.
- If anything is unclear, ask the user for clarification before continuing. Don't guess intent.
- If reasoning or context would help prioritize, ask for it.

### 2b. Cross-reference against project state
- Read `docs/PROJECT-PLAN.md` — check if the request duplicates, extends, or conflicts with existing tasks.
- Read `docs/reference/version-matrix.md` — for app-related requests, check if the component is already tracked.
- Check the current Flux/K8s manifests if needed to understand what's already deployed.

### 2c. Triage and assess

For each item, determine:

| Field | Description |
|-------|-------------|
| **Summary** | One-line description |
| **Type** | New app, config change, reorganization, infrastructure, documentation |
| **Effort** | S (< 30 min), M (30 min - 2 hrs), L (> 2 hrs) |
| **Priority** | P0 (blocking/broken), P1 (should do this session), P2 (next session), P3 (backlog) |
| **Phase** | Which PROJECT-PLAN.md phase this belongs to (or "New phase") |
| **Dependencies** | Other tasks or components this depends on |
| **Risks** | Architecture conflicts, breaking changes, resource constraints |

### 2d. Suggest improvements or alternatives

- If you see a better approach than what was requested, suggest it with reasoning.
- If the request conflicts with current architecture, explain the conflict and propose a resolution.
- If multiple requests interact (e.g., reorganizing dashboard + adding new apps), note the interaction and suggest an order.

## 3. Present analysis

Present the triage table to the user. For each item:
- Show the assessment from step 2c.
- Note any questions, risks, or alternatives.
- Recommend whether to proceed, defer, or modify.

Wait for the user to approve, reject, or modify each item before proceeding.

## 4. Analyze document format

- Review the structure and layout of the update file(s).
- Compare against the template in `docs/user-updates/TEMPLATE.md`.
- If the user's natural format reveals useful patterns not in the template, suggest template improvements.
- If the document would have been clearer with the template structure, note that (but don't nag — quick ideas are fine).

## 5. Incorporate agreed updates

For each approved item:
- Add it to the appropriate section in `docs/PROJECT-PLAN.md` with a checkbox `[ ]`.
- If it belongs to an existing phase, add it under the right subsection.
- If it's a new category, create a subsection.
- Update the dependency graph if the new task has ordering requirements.
- For app-related items, add/update the row in `docs/reference/version-matrix.md` if applicable.

## 6. Archive processed file

- Move the processed file to `docs/user-updates/_processed/` with a date prefix:
  `mv docs/user-updates/Foo.md docs/user-updates/_processed/YYYY-MM-DD-Foo.md`
- This preserves the original for reference without cluttering the intake queue.

## 7. Summary

Report what was done:
- Number of items processed (approved / deferred / rejected).
- Files updated (PROJECT-PLAN.md, version-matrix.md, etc.).
- Any follow-up questions or deferred items to revisit.
