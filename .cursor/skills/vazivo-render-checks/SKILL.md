---
name: vazivo-render-checks
description: >-
  Verify the final Vazivo/storebrief deployment SHA and diagnose observed Render
  failures. Use for production questions or after a delivery wave's final merge.
---

# Vazivo Render verification

App: `storebrief`, auto-deployed from `main`. Check once after the final merge in
an authorized wave; repeat only for a failure, relevant change or user request.
Load [reference.md](reference.md) for resource IDs or migration failure guidance.

## Access and status

Prefer configured Render tools; otherwise use the CLI. Probe access once. Install
a CLI only if needed and credentials are known available; never print secrets or
start interactive login automatically. If access is unavailable, report once,
cache that result and continue repository work. Retry on an access change or
explicit user retry.

```bash
# CLI fallback, when configured:
render whoami
render deploys list srv-dat4n4p42hec73fg8ksg -o json
```

Compare the latest deployment's SHA with the intended final `main` SHA. Summarize
status and SHA only. For an active build/deploy, use one watcher or 30–60s polling;
avoid repeated service discovery. Slow startup alone does not justify cancellation,
restart or redeploy.

## Diagnose an observed failure

On `build_failed` / `update_failed`, fetch bounded logs for that deploy's time
window. Identify the cause before editing or retrying. Inspect deployed migration
versions when relevant; preserve existing data and avoid renaming applied migrations.
Use the normal branch/PR/CI workflow for fixes, then verify the resulting deploy.
Manual redeploy needs a concrete reason and existing authorization.

## Report evidence precisely

Report `live` only for a confirmed matching deployment SHA. A public `/up` response
or new asset does not establish which commit is live. A timed-out health request
alone does not establish an outage; use a bounded retry when needed. Distinguish
merged code, local/CI results, public health and production verification. If access
is missing, state that the production commit remains unverified.
