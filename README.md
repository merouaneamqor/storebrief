# Vazivo

**Vazivo** is Czech for connective tissue. As a product, it is connective tissue for retail networks: the layer that links head office, regions, and stores so instructions, work, and proof can flow.

Multi-tenant Rails app for sending **news** and **task** briefs across a region → area → store hierarchy — with a **Morocco first release**: French/Arabic (+ RTL), offline checklists, WhatsApp task alerts (stub), and bilingual store templates.

## Stack

- Rails 8 + PostgreSQL + Active Storage
- Docker Compose (`web`, `db`, Mailcatcher)
- Hotwire + Alpine.js + IndexedDB offline queue

## Quick start

```bash
docker compose up --build
```

Marketing landing (FR/AR): [http://localhost:3001](http://localhost:3001)  
Signed-in app: [http://localhost:3001/app](http://localhost:3001/app) · Login: [http://localhost:3001/login](http://localhost:3001/login)  
Mailcatcher: [http://localhost:1080](http://localhost:1080)

## Demo logins

Password for all accounts: `password`

| Tenant | Slug | Role | Email | Locale |
|--------|------|------|-------|--------|
| Atlas Retail Maroc | `atlas` | HQ | `hq@atlas.test` | FR |
| Atlas Retail Maroc | `atlas` | Store | `store@atlas.test` | AR (+ WhatsApp stub) |
| Contoso Shops | `contoso` | HQ | `hq@contoso.test` | FR |

## Morocco first-release demo

1. Sign in as Atlas HQ → toggle **FR / عربي** (RTL flips for Arabic)
2. Open **Modèles / القوالب** → use **Ouverture / الافتتاح** → send to a region/store
3. On the checklist show page, see **WhatsApp stub** notifications for the store user
4. Sign in as store (`store@atlas.test`) → **Mes checklists** → fill items (photo compressed client-side)
5. Simulate offline: DevTools → Offline → complete an item → go online → sync chip clears queued work
6. Sign in as Contoso HQ → confirm Atlas data is not visible

## Morocco GTM

90-day marketing strategy (Vazivo, Morocco): [`docs/morocco-90-day-marketing-strategy.md`](docs/morocco-90-day-marketing-strategy.md)  
Ideal customers: [`docs/ideal-customers.md`](docs/ideal-customers.md)  
Public summary: [http://localhost:3001/resources](http://localhost:3001/resources)

## Features

- Public Morocco landing page (demo request form, FR/AR RTL, product walkthrough)
- Tenant isolation
- Per-tenant feature flags + SAML SSO (Admin → **Feature flags**, or Brand → Features / SSO)
- Org hierarchy + communications (bilingual FR/AR fields)
- Checklist templates (opening, closing, cleanliness, safety, promotions, equipment, store visit)
- Offline checklist responses via IndexedDB → `POST /sync/checklist_responses`
- WhatsAppNotifier stub → `notification_logs`

## SAML SSO (per brand)

Each tenant can use its own IdP. Platform admins configure this under **Admin → Feature flags** (enable **SAML SSO**) and **Admin → Brand → SSO (SAML)**:

1. **Feature flags** → enable **SAML SSO** for the brand
2. **Brand → SSO (SAML)** → IdP entity ID, SSO URL, signing cert, optional enforce

Register these SP URLs with the IdP (replace `{slug}` and host):

| Field | URL |
|-------|-----|
| Entity ID | `https://{APP_HOST}/saml/{slug}` |
| ACS | `https://{APP_HOST}/saml/{slug}/acs` |
| Metadata | `https://{APP_HOST}/saml/{slug}/metadata` |

Users must already exist in that tenant (matched by email from NameID or the configured attribute). Password login remains unless **SSO enforced** is on. Set `APP_HOST` (and optionally `APP_URL`) so ACS URLs match production.

## Local env

Copy `.env.example` if you run outside Compose. Default database URL:

`postgres://store_brief:store_brief@localhost:5432/store_brief_development`

## Tests

```bash
TEST_DB=postgres://store_brief:store_brief@db:5432/store_brief_test

# Unit + integration
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=$TEST_DB web bin/rails db:test:prepare test

# Browser smoke (system tests) against a Chromium container
docker run -d --rm --name storebrief-selenium --network draft_default --shm-size 2g selenium/standalone-chromium
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=$TEST_DB \
  -e SELENIUM_REMOTE_URL=http://storebrief-selenium:4444 web bin/rails test:system
```

Without `SELENIUM_REMOTE_URL`, system tests use a local headless Chrome (as on CI). Failure screenshots land in `tmp/screenshots`.
