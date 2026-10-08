# CLAUDE.md — Vazivo

Project instructions for Claude Code (and compatible agents). Full conventions live in [AGENTS.md](./AGENTS.md); follow both.

## What this repo is

Rails 8 multi-tenant app (**Vazivo**) for retail HQ → store execution. Current focus: **Morocco ops** (FR + AR/RTL): radar, awareness, proof, customizable playbooks, rankings, multi-channel billing.

Not Store Excellence. No Darija in UI. No WhatsApp→task intake bridge.

## Quick orientation

```
app/services/vazivo/     # domain: radar, hq_board, playbooks, billing, ranking…
app/views/playbooks/     # customizable campaign sequences
app/views/dashboard/     # HQ board + store radar
config/locales/morocco.* # Morocco copy (keep en/fr/es/ar in sync)
app/assets/stylesheets/_morocco.scss
```

## How to work here

1. Use **Docker Compose** for Rails, DB, and tests — not ad-hoc host gemsets.
2. Scope everything by **tenant**. Use `tenant_scope` / `current_tenant`.
3. After SCSS: `docker compose exec web bin/rails dartsass:build`.
4. Tests:

```bash
docker compose exec -T web bash -lc \
  'RAILS_ENV=test DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_test \
   bin/rails test test/integration/vazivo_morocco_test.rb'
```

5. Locales: user-facing strings need FR/EN/ES/AR (Morocco keys in `morocco.*.yml`). No em dashes in UI copy.
6. Icons: Lucide SVGs in `app/assets/images/icons/` + `IconHelper::ICONS`.
7. Billing: email + WhatsApp billed; **push is free**.
8. Playbooks: `ensure_defaults!` must not wipe HQ customizations; custom keys allowed; starters resettable.

## Product constraints (hard)

- Verdicts: `conforme` | `improve` | `non_conforme`
- Feature flag for Morocco surfaces: `morocco_ops`
- Prefer Alpine on ERB pages; match existing HQ/store visual language
- Do not commit secrets; do not force-push `main`

## Roadmap delivery

Each session: sync GitHub Project/epics, pick Ready issues, implement (agents/worktrees), open PRs, merge when CI is green, then verify Render `storebrief` deploys. See `.cursor/rules/gh-epic-delivery.mdc`, `.cursor/skills/vazivo-gh-delivery/SKILL.md`, and `.cursor/skills/vazivo-render-checks/SKILL.md`.

## When unsure

Read `README.md` and `AGENTS.md` before inventing structure. Extend `Vazivo::` services and existing controllers rather than parallel stacks.
