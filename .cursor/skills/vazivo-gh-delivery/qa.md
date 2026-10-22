# Browser QA reference

Use only when changed behavior requires browser coverage. Reuse a healthy local
preview and existing QA data; reseed only when needed. Test setup must not reset
another agent's data. Prepare/migrate the database in a separate process from tests.

Local target: `http://localhost:3001`. QA slug: `qa-vazivo`; password: `password`.
Accounts: `hq@qa-vazivo.test`, `area@qa-vazivo.test`, `store@qa-vazivo.test`.
These are local fixtures, not proof of production access.

```bash
docker compose exec -T web bin/rails db:migrate
docker compose exec -T web bin/rails runner script/qa_tenant.rb
# Build once when missing/stale, including in newly mounted worktrees:
docker compose exec -T web bin/rails active_admin:bundle_js dartsass:build
```

Wait for `/up` before starting browser checks. Use installed Playwright/Chromium
or the available integrated browser; avoid a second browser installation.
If the installed browser is outside Playwright's default cache, use a local
configuration with `launchOptions.executablePath`; otherwise install the locked
browser version once. Do not assume a system Chromium is discovered automatically.

Choose checks for the change:

- HQ: changed compose, targeting, review or reporting behavior.
- Area: descendant-store scope and relevant monitoring actions.
- Store: own work, completion/proof flow and absence of HQ actions.
- FR/AR: translated copy, RTL and mobile overflow where affected.
- Offline changes: real offline/reconnect, persisted files, account isolation,
  retry failures and duplicate prevention.

Reuse existing passing coverage. Screenshot failures or visual changes only;
settle layout transitions first. Diagnose failures before filing an application
bug; distinguish fixture/setup/network problems from product regressions. Report
pass/fail/not-run and remaining blockers without claiming untested coverage.
