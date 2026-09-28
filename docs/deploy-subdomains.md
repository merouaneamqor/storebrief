# Deploy StoreBrief on one server with tenant subdomains

One Rails process serves every brand. The hostname picks the tenant.

| Host | What it serves |
| --- | --- |
| `storebrief.com` | Marketing site and login (tenant slug still required) |
| `atlas.storebrief.com` | Atlas app |
| `casa-patisserie.storebrief.com` | Casablanca Pâtisserie app |

`www` redirects to the apex host. `admin`, `mail`, and `api` are reserved and are not tenant slugs.

## DNS

Point the apex and a wildcard at the server:

```text
A    storebrief.com       YOUR_SERVER_IP
A    *.storebrief.com     YOUR_SERVER_IP
```

## Environment

On the server, create `.env` next to `docker-compose.prod.yml`:

```bash
APP_HOST=storebrief.com
APP_TLD_LENGTH=1
SECRET_KEY_BASE=$(openssl rand -hex 64)
POSTGRES_PASSWORD=change-me
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=eu-west-3
AWS_S3_BUCKET=storebrief-uploads-production
```

`APP_TLD_LENGTH` is `1` for a `.com` domain. Use `0` only for `localhost` (`atlas.localhost`).

## Start

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

Caddy obtains HTTPS certificates for the apex and wildcard host. Rails listens only inside the Docker network.

Seed or create tenants whose `slug` matches the subdomain (`atlas`, `casa-patisserie`). Unknown subdomains return 404.

## SAML SSO

Per-tenant SAML ACS and metadata URLs are always on the **apex** host (`APP_HOST`), not the brand subdomain:

```text
https://storebrief.com/saml/atlas
https://storebrief.com/saml/atlas/acs
https://storebrief.com/saml/atlas/metadata
```

Configure IdP entity ID, SSO URL, and signing cert in ActiveAdmin (platform admin) under Brand → SSO (SAML). Optional `APP_URL` overrides the derived base URL if the public origin differs from `https://{APP_HOST}`.

## Local check

With the development stack and `APP_HOST=localhost` / `APP_TLD_LENGTH=0`:

- http://localhost:3001 — marketing, login asks for a brand slug
- http://atlas.localhost:3001 — Atlas only (no slug field)
- http://www.localhost:3001 — redirects to localhost
