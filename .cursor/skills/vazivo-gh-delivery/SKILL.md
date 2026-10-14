---
name: vazivo-gh-delivery
description: >-
  Runs the Vazivo GitHub epic delivery loop: sync Project/epics/issues with gh,
  pick Ready tasks, launch parallel subagents per issue, open PRs, rebase through
  conflicts, squash-merge when CI is green, and mark Project Done. Use at session
  start, when continuing roadmap/P0/P1/P2 work, when organizing epics, or when
  the user asks to check tickets, ship issues, or merge PRs.
---

# Vazivo GitHub epic delivery

Repo: `merouaneamqor/storebrief`  
Project: [Vazivo Capability Roadmap](https://github.com/users/merouaneamqor/projects/6) (owner `merouaneamqor`, number `6`)

For field IDs, labels, and issue body templates see [reference.md](reference.md).

## Session checklist

Copy and track:

```
Delivery:
- [ ] Auth/scopes OK (repo + project)
- [ ] Synced epics/Ready/In progress/open PRs
- [ ] Chose N Ready issues (no file overlap)
- [ ] Agents/branches/worktrees started
- [ ] Each issue: comment + In progress
- [ ] PRs open, CI green
- [ ] Rebased if DIRTY after sibling merges
- [ ] Squash-merged + issues closed + Done
- [ ] Render live on expected SHA
- [ ] Browser QA on QA tenant (pass/fail notes)
```

## Phase 0 — Prerequisites

```bash
gh auth status
gh project list --owner merouaneamqor
# If project write fails:
# gh auth refresh -h github.com -s read:project,project
```

## Phase 1 — Sync (every session)

```bash
gh issue list --repo merouaneamqor/storebrief --state open --label epic --limit 30
gh issue list --repo merouaneamqor/storebrief --state open --label P0 --limit 40
gh pr list --repo merouaneamqor/storebrief --state open --limit 20
gh project item-list 6 --owner merouaneamqor --limit 50
```

Summarize for the user: epics open, Ready count, In progress, open PRs, blockers.

**Do not** create a shadow backlog in chat-only todos. GitHub is source of truth.

## Phase 2 — Organize (only if board empty / user asks)

1. Ensure labels: `P0` `P1` `P2` `epic` `task` `module:*` `status:exists|partial|missing`
2. Milestones: `P0 — Core Vazivo`, `P1 — Competitive parity`, `P2 — Platform`
3. Epics = parent issues (`epic` label); children = `task` with Parent `#epic` in body
4. Add all to Project; set Priority + Module fields; Status `Backlog` or `Ready`
5. Capability parity only — no YOOBIC branding/UI/copy

## Phase 3 — Select work

Pick **3–4 independent Ready** children (prefer P0). Avoid overlapping files:

| Safe parallel slices | Avoid colliding on |
|----------------------|--------------------|
| New models/controllers | Same `schema.rb` migration time |
| Distinct `Vazivo::` services | Same locale keys / same partial |
| Separate view trees | `icon_helper.rb` / `_morocco.scss` without merge plan |

Mark each **In progress** on Project; comment: `Picked up by agent for implementation.`

## Phase 4 — Execute (subagents)

One Task subagent (or one focused thread) **per issue**:

- Branch: `feature/<issue>-short-slug` from latest `main`
- Prefer **git worktree** (`../draft-wt-<n>`) when multiple agents share the machine
- Implement MVP matching acceptance criteria; extend `Vazivo::` / existing models
- Tests: Docker Compose (see AGENTS.md); locales FR/EN/ES/AR; tenant_scope; `morocco_ops` when needed
- `gh pr create` with body `Closes #<n>` or `Fixes #<n>`
- Comment PR URL on the issue

Subagent prompt must include: issue number, acceptance criteria, code anchors, out-of-scope, branch name, worktree note, “do not touch sibling agents’ files.”

## Phase 5 — Merge path (do not stop early)

When user wants ship/merge (default for “continue delivery”):

1. `gh pr checks <n>` — all SUCCESS
2. `mergeable` + `mergeStateStatus: CLEAN`
3. If `DIRTY`/`CONFLICTING` after another merge:
   - `git fetch && git rebase origin/main`
   - Resolve keeping **both** sides when additive (icons, SCSS blocks, locale keys, schema columns)
   - For `schema.rb`: keep latest `version`, union tables/columns/FKs from both
   - `git push --force-with-lease`
4. `gh pr merge <n> --squash --delete-branch`
5. Merge **sequentially** when PRs touch shared files; wait for GitHub to recalculate between merges
6. Close issue if not auto-closed; set Project status **Done**
7. `git checkout main && git pull`
8. **Render** — follow **vazivo-render-checks**: confirm `storebrief` deploy is `live` on the new SHA; if `update_failed`, fix migrations/logs and redeploy via push
9. **Browser QA** — follow Phase 5b before declaring the wave done

## Phase 5b — Browser QA (Cursor integrated browser)

After merges (or before marking Project Done on user-facing work), smoke-test on the dedicated **QA tenant**.

### QA tenant

Slug: `qa-vazivo` · password: `password`

| Role | Email |
|------|-------|
| HQ | `hq@qa-vazivo.test` |
| Area | `area@qa-vazivo.test` |
| Store | `store@qa-vazivo.test` |

Ensure / recreate locally:

```bash
docker compose run --rm --no-deps \
  -e RAILS_ENV=development \
  -e DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_development \
  web bash -lc 'bin/rails db:migrate && bin/rails runner script/qa_tenant.rb'
```

Target URL: local `http://localhost:3001` (Compose / preview). Prefer local over Render for interactive QA; still verify Render deploy SHA separately.

### Smoke checklist (Cursor browser)

Use `cursor-ide-browser`: navigate → lock → snapshot → interact → screenshot on failures.

1. **Login HQ** (`qa-vazivo` / `hq@qa-vazivo.test`) → accept privacy if prompted → `/app` loads without 500
2. **My Tasks / nav** — HQ or store sees expected morocco_ops chrome (no Darija, no YOOBIC)
3. **HQ compose targets** — filters for role / format / cluster + dry-run preview when #34-shipped
4. **Templates** — `/templates` lists; new/edit audit template sections/questions when #43-shipped
5. **Area login** (`area@qa-vazivo.test`) → area summary + store status table + open a store radar
6. **Store login** (`store@qa-vazivo.test`) → radar / My Tasks / inbox open without HQ leak
7. Note **pass / fail** per role in the delivery report; file a GitHub issue for any fail (do not silently skip)

## Phase 6 — Report

Return a table: Issue | PR | Merged? | Notes. Include Browser QA pass/fail. Point at next Ready items.

## Anti-patterns

- Implementing without an issue number
- Parallel agents on the same branch/checkout without worktrees
- Leaving PRs open when the user asked to merge
- Force-push to `main`
- Restoring WhatsApp intake / Darija / YOOBIC clone UX
