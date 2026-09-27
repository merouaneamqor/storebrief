# StoreBrief

Multi-tenant Rails prototype for sending **news** and **task** briefs to stores across a region → area → store hierarchy.

## Stack

- Rails 8 + PostgreSQL
- Docker Compose (`web`, `db`, Mailcatcher)
- Hotwire + Alpine.js

## Quick start

```bash
docker compose up --build
```

App: [http://localhost:3001](http://localhost:3001)  
Mailcatcher: [http://localhost:1080](http://localhost:1080)

On boot the web service prepares the database and loads seeds.

## Demo logins

Password for all accounts: `password`

| Tenant | Slug | Role | Email |
|--------|------|------|-------|
| Northwind Retail | `northwind` | HQ | `hq@northwind.test` |
| Northwind Retail | `northwind` | Store | `store@northwind.test` |
| Contoso Shops | `contoso` | HQ | `hq@contoso.test` |
| Contoso Shops | `contoso` | Store | `store@contoso.test` |

Sign in with **tenant slug + email + password**. Data is isolated per tenant — Contoso HQ cannot see Northwind briefs.

## Demo flows

1. Sign in as Northwind HQ → dashboard, org tree, recent briefs
2. Compose a brief → choose news/task → select region or stores → Send
3. Sign in as Northwind store → inbox → mark news read / task complete
4. Back as HQ → open the brief → see delivery completion counts
5. Sign in as Contoso HQ → confirm Northwind data is not visible

## Local env

Copy `.env.example` if you run outside Compose. Default database URL:

`postgres://store_brief:store_brief@localhost:5432/store_brief_development`
