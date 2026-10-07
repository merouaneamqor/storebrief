# AGENTS.md — Vazivo

Guidance for AI coding agents working in this repository.

## Product

**Vazivo** is multi-tenant retail connective tissue: head office → regions → stores for briefs, tasks, checklists, proof, and execution visibility.

Primary market for the current product surface: **Morocco retail ops** (French + Arabic, RTL). Do not rebrand this as Store Excellence or reintroduce Darija in UI copy.

## Stack

- Rails **8.1**, PostgreSQL, Active Storage, Propshaft
- Hotwire (Turbo + Stimulus), **Alpine.js** for UI state, importmap
- Dart Sass (`bin/rails dartsass:build` after SCSS changes)
- Docker Compose (`web`, `db`, Mailcatcher) — prefer Compose over host Ruby for run/test
- Locales: `fr` (default), `en`, `es`, `ar` (+ Morocco keys in `config/locales/morocco.*.yml`)

## Layout (where things live)

| Area | Path |
|------|------|
| Morocco / ops domain services | `app/services/vazivo/` |
| Feature flags on tenant | `app/models/tenant.rb` (`FEATURE_FLAGS`, e.g. `morocco_ops`) |
| HQ board / store radar | `app/services/vazivo/hq_board.rb`, `radar.rb` |
| Playbooks | `app/models/playbook.rb`, `app/controllers/playbooks_controller.rb`, `app/views/playbooks/` |
| Billing (email + WhatsApp; push free) | `app/services/vazivo/billing.rb`, `app/controllers/billings_controller.rb` |
| App chrome / nav | `app/views/layouts/application.html.erb` |
| Morocco styles | `app/assets/stylesheets/_morocco.scss` |
| Icons (local Lucide subset) | `app/helpers/icon_helper.rb`, `app/assets/images/icons/` |

## Conventions

### Rails

- Multi-tenant: always scope through `tenant_scope` / `current_tenant`. Never leak cross-tenant data.
- HQ actions: `require_hq` (+ feature gates like `require_feature!(:morocco_ops)`).
- Bilingual fields: FR required, AR optional (`Bilingual` concern). Prefer `title_fr` / `title_ar` over inventing locale columns.
- Verdicts use `conforme` / `improve` / `non_conforme` — not Darija labels.
- Prefer existing services under `Vazivo::` over new ad-hoc controllers logic.
- Migrations: timestamped under `db/migrate/`; keep `db/schema.rb` in sync.

### Front end

- ERB + Alpine for interactive panels; Stimulus only where already used.
- Rebuild CSS with `docker compose exec web bin/rails dartsass:build` after stylesheet edits.
- New icons: add SVG under `app/assets/images/icons/` **and** register in `IconHelper::ICONS`.
- UI copy: no em dashes; empty values show `-`. Keep FR/AR/EN/ES locales in sync for user-facing strings.
- Match existing design tokens in `_tokens.scss` / `_app.scss`; avoid one-off purple/glow AI aesthetics.

### Notifications & billing

- Push notifications are free.
- Platform email and WhatsApp alerts are billable (`NotificationLog.billed`, `Vazivo::Billing`).
- Do **not** restore WhatsApp → task intake / paste bridge (removed on purpose).

### Playbooks

- Starters: `aid`, `sale`, `black_friday` — seed via `Playbook.ensure_defaults!` without overwriting customizations.
- HQ can customize steps (offset days, titles, photo flags), create custom playbooks, reset starters, delete custom ones.
- Deploy via `Vazivo::PlaybookDeployer`.

## Commands

```bash
# App
docker compose up --build

# Assets
docker compose exec web bin/rails dartsass:build

# Tests (integration / unit)
docker compose exec -T web bash -lc \
  'RAILS_ENV=test DATABASE_URL=postgres://store_brief:store_brief@db:5432/store_brief_test \
   bin/rails test path/to/test.rb'

# Seeds
docker compose exec web bin/rails db:seed
```

Demo password: `password`. Atlas HQ: `hq@atlas.test` (slug `atlas`). See README for more accounts.

## Delivery process (GitHub)

Roadmap work uses GitHub epics → Ready issues → feature branches/subagents → PR → CI → squash-merge → Project **Done**.

- Always-on rule: [`.cursor/rules/gh-epic-delivery.mdc`](.cursor/rules/gh-epic-delivery.mdc)
- Full skill: [`.cursor/skills/vazivo-gh-delivery/SKILL.md`](.cursor/skills/vazivo-gh-delivery/SKILL.md)
- Render skill: [`.cursor/skills/vazivo-render-checks/SKILL.md`](.cursor/skills/vazivo-render-checks/SKILL.md)
- Board: [Vazivo Capability Roadmap](https://github.com/users/merouaneamqor/projects/6)

At session start, sync the board with `gh` before inventing work. After merges to `main`, verify the Render `storebrief` deploy.

## Do / don't

**Do**

- Follow existing folder structure, naming, and ERB partial patterns.
- Gate Morocco surfaces behind `morocco_ops` (and related flags).
- Add/update tests next to behavior you change (`test/integration`, `test/services`).
- Keep agent docs (`AGENTS.md`, `CLAUDE.md`) accurate when product rules change.
- Follow the GitHub epic delivery loop for roadmap/feature work (see above).

**Don't**

- Commit `.env` or secrets.
- Push to `main` without an explicit ask; prefer a feature branch.
- Reintroduce Darija, WhatsApp intake paste flow, or Store Excellence naming in Morocco UX.
- Invent new design systems when `_morocco.scss` / `_app.scss` already cover the surface.
- Run destructive git commands (`push --force`, hard reset) unless explicitly requested.

## PR / commit hygiene

- Commit only when asked; message focuses on **why**.
- Do not amend commits you did not create in the current session, or already-pushed commits, unless asked.
- After substantive Ruby/ERB/SCSS changes, run the relevant tests and `dartsass:build` locally via Compose.
