# Vazivo GH delivery — reference

## Project constants

| Item | Value |
|------|--------|
| Repo | `merouaneamqor/storebrief` |
| Project number | `6` |
| Project URL | https://github.com/users/merouaneamqor/projects/6 |
| Project node id | `PVT_kwHOAj2lVc4BmFjB` |

### Status field (`Status`)

Field id: `PVTSSF_lAHOAj2lVc4BmFjBzhkv6hU`

| Option | Id |
|--------|-----|
| Backlog | `f75ad846` |
| Ready | `92db496e` |
| In progress | `47fc9ee4` |
| Blocked | `f4a826fa` |
| Done | `98236657` |

### Priority field

Field id: `PVTSSF_lAHOAj2lVc4BmFjBzhkv6pA` — options P0 `0c581836`, P1 `486efa74`, P2 `27da4e8b`

### Module field

Field id: `PVTSSF_lAHOAj2lVc4BmFjBzhkv6pY` — options: tasks, visits, vm, campaigns, comms, academy, kb, ai, hq-radar, store-dash, regional, integrations

## Set Project status

```bash
# Resolve item id for issue N
ITEM=$(gh api graphql -f query='
query($p:ID!){
  node(id:$p){
    ... on ProjectV2 {
      items(first:100){
        nodes{ id content{ ... on Issue { number } } }
      }
    }
  }
}' -f p=PVT_kwHOAj2lVc4BmFjB --jq ".data.node.items.nodes[] | select(.content.number==N) | .id")

gh api graphql -f query='
mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){
  updateProjectV2ItemFieldValue(input:{
    projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}
  }){ projectV2Item { id } }
}' -f p=PVT_kwHOAj2lVc4BmFjB -f i="$ITEM" \
  -f f=PVTSSF_lAHOAj2lVc4BmFjBzhkv6hU -f o=47fc9ee4   # In progress
```

## Child issue body template

```markdown
## Parent
- Epic: #<epic>

## Goal
…

## Acceptance criteria
- [ ] …

## Code anchors
- `path/...`

## Out of scope
- No YOOBIC branding, UI clone, or proprietary copy
- Keep Vazivo FR/AR UX; verdicts conforme / improve / non_conforme
- Tenant-scoped; gate Morocco surfaces with morocco_ops
```

## Worktree pattern

```bash
cd /home/mamqor/projects/draft
git fetch origin
git worktree add ../draft-wt-<n> -b feature/<n>-slug origin/main
# implement + test in worktree (own DATABASE_URL suffix if needed)
# after PR merged:
git worktree remove ../draft-wt-<n> --force
```

## Merge wait loop (sketch)

```bash
# After push, poll until CLEAN + checks SUCCESS, then:
gh pr merge <n> --repo merouaneamqor/storebrief --squash --delete-branch
```

## Test command (Compose)

```bash
docker compose exec -T web bash -lc \
 'RAILS_ENV=test DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_test \
  bin/rails test path/to/test.rb'
```

## Epics map (as of board scaffold)

| # | Epic | Priority |
|---|------|----------|
| 18 | Task Management | P0 |
| 19 | Store Visits & Audits | P0 |
| 20 | Promotions & Campaigns / Playbooks | P0 |
| 21 | HQ Radar / Intelligence | P0 |
| 22 | Store Manager Dashboard | P0 |
| 23 | Regional Manager | P0 |
| 24 | Visual Merchandising | P1 |
| 25 | Communications | P1 |
| 26 | Knowledge Base | P1 |
| 27 | Vazivo Academy | P2 |
| 28 | AI / Store Intelligence | P2 |
| 29 | Integrations & API | P2 |

Re-query with `gh issue list --label epic` if numbers drift.
