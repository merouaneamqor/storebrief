---
name: vazivo-render-checks
description: >-
  Checks and troubleshoots Render deploys for Vazivo/storebrief using the Render
  CLI: list services, inspect deploy status, fetch failure logs, fix common
  migration deploy breaks, and confirm live commits. Use when the user asks about
  Render, deploys, production, live status, deploy failures, or after merging to
  main.
---

# Vazivo Render checks

Primary app: **storebrief** on Render (auto-deploys from `main`).  
CLI: `render` (v2+). Auth: `render whoami` / `render login`.

Resource IDs and status meanings: [reference.md](reference.md).

## When to run

- User asks to check Render / deploys / production
- After squash-merge to `main` (pair with **vazivo-gh-delivery**)
- Deploy shows `update_failed` / `build_failed`

## Checklist

```
Render:
- [ ] render whoami OK
- [ ] Latest storebrief deploy status + commit
- [ ] If failed: pull logs, identify root cause
- [ ] Fix on main (prefer idempotent migrations)
- [ ] Confirm new deploy is live on expected SHA
```

## Phase 1 — Status

```bash
render whoami
render services -o text
render deploys list srv-dat4n4p42hec73fg8ksg -o json
```

Summarize the latest few deploys: **status**, commit SHA + subject, trigger, finishedAt.

Healthy after a merge: newest deploy `live` (or `build_in_progress` / `update_in_progress` then poll) on the expected `main` SHA.

## Phase 2 — Failure logs

On `update_failed` / `build_failed`:

```bash
# Window around deploy start/finish from the deploy JSON
render logs -r srv-dat4n4p42hec73fg8ksg \
  --start <ISO> --end <ISO> --limit 200 -o text
```

Search for: `Migrating to`, `rails aborted`, `PG::`, `DuplicateColumn`, `DuplicateMigration`, `Exited with status`.

Also check cron if relevant: `storebrief-push-reminders` (`crn-datptpmk1f9s7397mo90`).

## Phase 3 — Common fixes (this app)

### Duplicate migration timestamp / rename

Renaming a migration that **already ran in prod** makes Rails treat it as new → `PG::DuplicateColumn` (or similar).

**Do:**

1. Make the renamed migration **idempotent** (`return if column_exists?(:table, :col)`).
2. If another migration reused the old version number, give it a **new** timestamp so it is not skipped behind the existing `schema_migrations` row.
3. Bump `db/schema.rb` version; commit; push `main`; poll deploy until `live`.

### Migration already applied under old version

Never rely on filename alone. Check whether the **version** is already in `schema_migrations` on Render (symptoms: column exists but new file with same version never runs, or renamed file re-runs).

### Build failures

Read build logs the same way; fix Dockerfile / assets / `dartsass` / bundle as indicated. Do not force-push `main`.

## Phase 4 — Poll until settled

```bash
# Repeat until status is live | update_failed | build_failed | canceled
render deploys list srv-dat4n4p42hec73fg8ksg -o json
```

Report: live SHA vs `git rev-parse origin/main`, and whether the merge is actually in production.

## Phase 5 — Optional actions

```bash
# Manual redeploy (only if user asks or auto-deploy stuck)
render deploys create srv-dat4n4p42hec73fg8ksg

# Recent app logs
render logs -r srv-dat4n4p42hec73fg8ksg --limit 100 -o text
```

Do **not** restart/redeploy destructively without a clear reason.

## Report format

| Service | Latest status | Commit | Note |
|---------|---------------|--------|------|
| storebrief | live / failed / in progress | `abc1234` subject | … |

If failed: root cause one-liner + fix PR/commit link.
