# Tenant OpenID Connect

OIDC is optional and defaults to off. Existing SAML configuration and login remain
available. A platform administrator enables the tenant's `oidc_sso` feature. Only
built-in HQ administrators or platform administrators can open `/oidc_settings`.
Custom HQ roles cannot configure identity providers or link accounts.

## Provider setup

Register a confidential web client at the trusted provider. Copy its exact issuer,
authorization endpoint, token endpoint and JWKS URI from the provider's published
configuration. Vazivo does not fetch discovery documents during configuration.
Register the exact callback URL shown in settings. If login is used on both the
apex host and a tenant subdomain, register both callback URLs. The authorization
request uses `openid email profile`, authorization code flow, PKCE S256, state and
nonce. Configure the provider to include a boolean `email_verified` and any
required group/site claims in the signed ID token.

Supported providers must return RS256 ID tokens with a `kid` matching a public RSA
JWKS signing key of 2048–8192 bits. Issuer, audience, authorized party, expiry,
issued-at, optional not-before and nonce are verified. HTTPS endpoints must use
port 443 and resolve exclusively to public addresses. Redirects are not followed.
The HTTP client retains configured proxy and CA trust, pins its validated target
address, verifies the original TLS hostname, and bounds time and response size.
Private-network providers and alternate HTTPS ports are not supported.

Client secrets and transient PKCE verifiers use authenticated AES-GCM encryption
with a separate purpose and a key derived from the application's existing
`SECRET_KEY_BASE`. Secrets are never populated into HTML or echoed on errors.
Blank secret edits preserve the existing value. After rotating `SECRET_KEY_BASE`,
re-enter client secrets and restart pending login flows. No provider credentials
or real provider configuration are seeded by the application.

## Provisioning and role policy

JIT account creation is separately opt-in. New accounts require a valid signed ID
token, a verified email, and at least one matching mapping. An existing account's
verified email must match and it cannot already belong to another issuer/subject.
The identity key is the tenant plus exact issuer and subject, not email alone.
Platform administrator accounts cannot authenticate through tenant OIDC.

Mappings match an exact string or an entry in a string-array claim:

```json
[
  {"claim":"groups","value":"store-rabat","role":"store","org_unit_id":123},
  {"claim":"site","value":"Rabat","tenant_role_id":456,"org_unit_id":123}
]
```

All target units and custom roles must belong to the tenant. Base `area` and
`store` roles are supported. HQ mappings must use a custom tenant HQ role;
groups can never create built-in HQ administrators. Custom capabilities and
organization subtree restrictions follow the normal tenant permission matrix.
Conflicting matched grants for the same unit deny login and revoke previous
SSO-managed grants. A conflicting manual membership is never overwritten.

At each verified OIDC login, previous memberships owned by that OIDC identity are
replaced with the currently matched grants. Losing all mappings denies login
and commits removal of those SSO-managed memberships. Unrelated manual
memberships remain unchanged. A matching manual membership can satisfy a mapping
without becoming SSO-managed. Changes to a managed membership through another
admin interface remain SSO-owned until the identity is unlinked.

Built-in HQ accounts cannot be automatically linked by email. An administrator
must explicitly prelink their exact provider subject in settings. A subsequent
verified token must still match that subject, issuer and account email. Explicitly
prelinked built-in HQ administrators retain their manual administrative membership
even without group mappings. This exception never creates a new HQ grant.

Role synchronization happens at login, not through SCIM or background provider
polling. Admins can unlink an identity to revoke its SSO-managed memberships
immediately; unlinking never removes manual memberships. Review manual grants
separately when offboarding a person. Enforcing SSO blocks tenant password login;
platform administrators retain their separate recovery login. SAML remains an
independent trusted login method when enabled.

Login attempts expire after five minutes, bind to the initiating browser and
tenant, issuer and client, and are consumed under a database row lock before
code exchange. Replays, expired attempts, wrong browser sessions and cross-tenant
callbacks fail closed. Tests use generated signing keys and stubbed IdP HTTP
responses; there is no production bypass or insecure development provider.
