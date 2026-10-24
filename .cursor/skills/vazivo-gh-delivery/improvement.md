# Self-improvement loop

Use when a delivery reveals an actionable lesson. This runs inside normal delivery,
not as a separate agent, scheduled job or recursive optimization task.

## Evidence → change → verify

1. Identify a user correction, workflow defect or recurring waste using existing
   logs, diffs and results. Separate tool/network failures from application bugs.
   Do not turn one unexplained incident into a universal rule.
2. State the smallest useful hypothesis: what should change, why it should help,
   and which correctness checks must remain. Prefer removing a duplicate step or
   correcting the canonical rule over adding another instruction.
3. Implement the change in the relevant skill/reference. Align companion rules
   only if they conflict. Put setup details in references loaded on demand.
   Never weaken tenant isolation, permissions, CI, merge checks or user scope to
   improve a speed metric. Preserve existing commit/merge authorization.
4. Validate links, examples, frontmatter, consistency and whitespace. For a code
   change, run affected behavior checks. Compare instruction size or other
   already-available measurements; distinguish word count from actual token,
   runtime or billing savings. Do not add telemetry work solely to fill a metric.
5. Include a concise explanation and evidence in the current PR when appropriate.
   After that PR has merged, use a focused follow-up PR only when the improvement
   warrants it. Keep changes reviewable; never silently rewrite `main` or grant
   new access. Apply the existing delivery workflow to future tasks.

Run one pass per batch. When a trial fails, revise or revert that trial before
proceeding; do not start repeated optimization loops. If there is no useful new
lesson, make no change and add no log entry. An improvement is verified only to
the extent supported by its checks; confirm its effect during later normal use.

## Bounded lesson record

Keep at most five entries below, at most 60 words each. Each must contain evidence,
the rule changed and actual validation. Update/deduplicate entries instead of
appending a session diary. Replace obsolete entries; exclude secrets and customer
data. Rules belong in the canonical workflow, not only in this record.

### 2026-10-22: duplicate work and blocked access

Evidence: #294–#296 required multiple checkouts with mounted assets and repeated
discovery/denied Project queries. Change: reuse state/images, cache access failures, and default
to one agent. Validation: documentation links and shell examples pass; core
instruction word count is measured. Operational savings remain to be measured
during ordinary delivery.

### 2026-10-22: slow CI downloads

Evidence: [run 39856831794](https://github.com/merouaneamqor/storebrief/actions/runs/39856831794)
was cancelled during a slow Ubuntu package download; retry required downloading
dependencies again and eventually passed. Change: diagnose progress, avoid
elapsed-time-only cancellation, and retry only affected jobs. Validation: the
failure guidance preserves expected-head and CI checks; retry succeeded.

### 2026-10-22: reuse the available browser

Evidence: repeated browser dependency downloads in run 39856831794 added setup
work. Change: CI reuses installed Chrome/Chromium, with the locked installer as
fallback; local checks use an executable-path environment variable. Validation:
the RTL browser test passed with system Chromium, and workflow YAML/shell checks
passed. Full CI remains the merge gate; runtime savings are not yet measured.

### 2026-10-23: register the current CI head before watching

Evidence: early watchers for #299/#303 exited with stale or missing checks after
a push. Change: confirm checks registered for the pushed SHA before starting one
watcher. Validation: #307 used this order and completed all six checks; merges
still verify the expected head. No token or runtime savings are claimed.


### 2026-10-24: settle Turbo navigation before recording links

Evidence: UX #316's FR/AR login check initially captured `/inbox` before task
navigation settled. Change: wait for the expected URL or destination content
before recording links. Validation: explicit `expect(page).toHaveURL(/inbox\/\d+$/)`
made both flows pass in 17 seconds. Existing permission and CI gates remain; no
savings are claimed.
