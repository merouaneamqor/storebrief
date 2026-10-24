# Delivery command reference

Read only the relevant section. Reuse equivalent connected tools when available.

## Compact discovery

Run independent reads together once; retain results in task context or ignored
scratch storage. Fetch bodies only for candidates. If a result reaches its limit,
page or narrow the query before treating the inventory as complete.

```bash
gh issue list --repo merouaneamqor/storebrief --state open --limit 100 \
  --json number,title,labels,milestone,assignees
gh pr list --repo merouaneamqor/storebrief --state open --limit 30 \
  --json number,title,headRefName,isDraft
gh project item-list 6 --owner merouaneamqor --limit 200 --format json \
  --jq '{totalCount,items:[.items[]|{id,status,title,number:.content.number}]}'
```

Cache Project authorization failures; retry only after an access change or user
retry. An unavailable board does not override the user's priority instruction.

## Branch and PR

Replace `ISSUE`, `PR_NUMBER` and `slug` with actual values; issue and PR numbers differ.

```bash
git fetch origin
git worktree add ../storebrief-wt-ISSUE -b feature/ISSUE-slug origin/main
# After implementation, commit/push according to user authorization and AGENTS.md.
# Write the exact multiline PR text to a file, including Closes #ISSUE.
gh pr create --repo merouaneamqor/storebrief --base main --head feature/ISSUE-slug \
  --title 'Describe the resulting behavior' --body-file /tmp/vazivo-pr-body.md
gh pr checks PR_NUMBER --repo merouaneamqor/storebrief --watch --interval 45
```

Use one CI watcher per head; keep repetitive output in a local log. A failed job
needs diagnosis before a targeted retry. Do not repeat successful jobs. Confirm
all applicable CI checks, current head and mergeability immediately before merging;
pass the expected head SHA when the selected tool supports it. Inspect actual
conflicts before updating a branch. Never force-push `main`.

## Shared runtime and tests

Reuse one compatible dependency image, with each checkout mounted separately.
Check image/lockfile compatibility; rebuild dependencies only when needed. Follow
managed-environment proxy/CA instructions for networked builds. A fresh bundle
volume can hide installed gems; a checkout mount can hide built assets.

- Separate test DB per parallel issue; cap total workers to available resources.
- Prepare the database in a separate command/process before running tests.
- Build assets only when missing or inputs change; reuse compatible artifacts.
- Use an existing browser, or install the locked Playwright browser once.
- Documentation-only changes need local link/command/whitespace checks, not local
  Rails suites. Required remote CI still applies before merge.

```bash
docker compose exec -T web bash -lc \
  'RAILS_ENV=test DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_test bin/rails db:test:prepare'
docker compose exec -T web bash -lc \
  'RAILS_ENV=test DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_test bin/rails test test/path_test.rb'
```

For parallel work, substitute the issue's DB and checkout/container. For a combined
wave, run broader coverage once when changes warrant it. See [qa.md](qa.md).

## Project fields

Project: `PVT_kwHOAj2lVc4BmFjB` (owner `merouaneamqor`, number `6`). Resolve item IDs
from the cached snapshot; avoid a new item-list query for every status update.
Revalidate field IDs if the Project schema changes.

| Field | ID | Options |
|---|---|---|
| Status | `PVTSSF_lAHOAj2lVc4BmFjBzhkv6hU` | Backlog `f75ad846`; Ready `92db496e`; In progress `47fc9ee4`; Blocked `f4a826fa`; Done `98236657` |
| Priority | `PVTSSF_lAHOAj2lVc4BmFjBzhkv6pA` | P0 `0c581836`; P1 `486efa74`; P2 `27da4e8b` |
| Module | `PVTSSF_lAHOAj2lVc4BmFjBzhkv6pY` | tasks, visits, vm, campaigns, comms, academy, kb, ai, hq-radar, store-dash, regional, integrations |

```bash
# ITEM_ID comes from the cached snapshot; this example sets In progress.
gh project item-edit --project-id PVT_kwHOAj2lVc4BmFjB --id "$ITEM_ID" \
  --field-id PVTSSF_lAHOAj2lVc4BmFjBzhkv6hU --single-select-option-id 47fc9ee4
```

Create/reorganize epics, labels or milestones only when requested or needed for
selected work. Use current GitHub evidence instead of a static epic-number map.
