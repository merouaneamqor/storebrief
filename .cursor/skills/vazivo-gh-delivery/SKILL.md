---
name: vazivo-gh-delivery
description: >-
  Deliver Vazivo roadmap issues through scoped implementation, verification,
  PRs and authorized merges. Reuse session state and runtime setup; delegate
  only when useful. Use for continuing roadmap work or shipping tracked issues.
---

# Vazivo delivery

Repo: `merouaneamqor/storebrief` · [Project #6](https://github.com/users/merouaneamqor/projects/6).
Read `AGENTS.md` once for product constraints. Reuse instructions already in context.
Load [reference.md](reference.md) only for commands or Project IDs, and
[qa.md](qa.md) only for browser setup. This workflow adds no approval gates;
honor the user's scope and existing authorization.

## 1. Sync once, then read changes

- Reuse the confirmed checkout, runtime and ongoing task state on follow-ups.
- Fetch compact open issue/PR metadata and Project items once. Fetch full bodies
  only for candidates. Cache issue/PR IDs, heads, checks and access failures.
  Refresh affected records after pushes/merges; resync the backlog for a new batch.
- Probe each required service once. Cache permission denials; retry after an
  access change or an explicit user retry. Prefer an available connector; use
  `gh`/REST when the required operation is unavailable there. Never print secrets
  or start interactive authentication automatically.
- If Project access is denied, continue authorized repository work. Follow a
  user-named issue or priority instruction without inventing a `Ready` status.
  Ask only if a missing decision actually blocks selection.

GitHub is the source of truth. Keep local state small; avoid a second backlog.

## 2. Select and implement

- Prefer Ready children, ordered P0 → P1 → P2, then dependencies and impact.
  Before coding, compare acceptance criteria with current code and merged PRs.
  Close already-fulfilled tickets with evidence; close an epic only when all its
  requirements and children are complete.
- Default to one agent. Delegate only substantial, independent issues when the
  benefit exceeds setup/review cost; normally at most 2–3 concurrent issues.
- One issue per feature branch. Use separate worktrees and test databases for
  parallel work. Plan shared files, migration timestamps and merge order first.
- A delegate receives the issue, acceptance criteria, owned paths, branch,
  shared runtime/test commands and finish line. Return a concise diff summary,
  test evidence, SHA and PR URL; avoid full-history duplication when a focused
  handoff suffices.
- Record pickup once; set Project `In progress` when accessible. Extend existing
  services and follow `AGENTS.md`. Reuse one dependency image across worktrees.

## 3. Verify proportionately

- Documentation-only edits: check accuracy, links, commands and whitespace.
  Application changes: focused behavior tests and lint for changed code; build
  assets when affected. Exercise tenant/role boundaries and relevant locales.
- For a multi-issue wave, run combined regression/browser coverage once after
  integration when cross-module risk warrants it. Skip a full baseline unless
  needed to diagnose existing failures. Reuse valid passing evidence; rerun
  only checks affected by subsequent changes or unresolved failures.
- For UI/permission changes, check affected HQ/area/store flows, FR/AR RTL and
  phone layout. Prefer existing Playwright coverage or the available browser.
  Capture screenshots for failures or visual review, not every passing step.

## 4. PR, CI and merge

- Open a focused PR with `Closes #N` and actual validation. Follow the requested
  finish line; continue an established delivery workflow through authorized merge.
- Wait for checks on the pushed SHA to register, then use one CI watcher per
  head (30–60s interval). Inspect failed-job logs before changing code or retrying.
- Slow dependency downloads are not proof of a hang. Do not cancel based on
  elapsed time alone. Retry only a failed/cancelled job, or recover a confirmed
  infrastructure stall; preserve successful jobs and avoid competing reruns.
- Before squash-merge, verify the expected head and mergeability; require all
  applicable CI checks to pass, including every required check.
  Wait for expected jobs to register; missing checks are not passing CI.
  Merge sequentially. Wait for GitHub to recalculate an unknown/stale state.
  Update a branch only for a real conflict or required base update; prefer merging
  `origin/main` to rewriting published history. Preserve additive changes and
  regenerate schema when appropriate; run affected checks after resolution.

## 5. Close and report

Confirm issue closure and Project `Done` when accessible; sync the local checkout.
After the final merge in a wave, use `vazivo-render-checks` once for the final SHA.
Reuse browser evidence when the merged result matches the validated content.
Report merged PRs, test results and actual blockers concisely. Distinguish local
QA, GitHub CI, public health and a verified production commit. Never claim
inaccessible Project updates or production verification; continue independent
work when a service is unavailable.

## 6. Improve from evidence

At delivery close, review friction using evidence already collected. For an
actionable lesson or user correction, follow [improvement.md](improvement.md) and
apply a small, validated workflow update through the authorized branch/PR flow.
Otherwise skip extra reads and edits. Run at most one improvement pass per batch;
retain merge, security and product checks.
