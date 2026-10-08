# Vazivo Render — reference

## Workspace

- CLI config: `~/.render/cli.yaml`
- Whoami: `render whoami`

## Resources (storebrief / Vazivo)

| Name | Type | ID |
|------|------|-----|
| storebrief | Web Service | `srv-dat4n4p42hec73fg8ksg` |
| vazivodb | Postgres | `dpg-dat4o4flk1mc73e91qeg-a` |
| storebrief-push-reminders | Cron Job | `crn-datptpmk1f9s7397mo90` |

Dashboard (web): `https://dashboard.render.com/web/srv-dat4n4p42hec73fg8ksg`

## Other workspace apps (do not confuse)

| Name | Type | ID |
|------|------|-----|
| morea | Web Service | `srv-dav7nqh42hec73dbphkg` |
| morea-db | Postgres | `dpg-dav7luflk1mc73f8gvrg-a` |
| morea-redis | Key Value | `red-dav7lrflk1mc73f8gks0` |
| morea-sendit-sync | Cron Job | `crn-davrv30u01pc73fu4hu0` |

Default checks target **storebrief** unless the user names another service.

## Deploy statuses (common)

| Status | Meaning |
|--------|---------|
| `build_in_progress` | Image/build running |
| `update_in_progress` | Deploy/migrate/restart running |
| `live` | Current production release |
| `update_failed` | Deploy/migrate failed (often `db:prepare`) |
| `build_failed` | Build/image failed |
| `deactivated` | Superseded by a newer deploy |
| `canceled` | Canceled |

## Useful commands

```bash
render services -o text
render deploys list srv-dat4n4p42hec73fg8ksg -o json
render deploys create srv-dat4n4p42hec73fg8ksg
render logs -r srv-dat4n4p42hec73fg8ksg --limit 100 -o text
render logs -r srv-dat4n4p42hec73fg8ksg --start 2026-10-07T16:42:00Z --end 2026-10-07T16:45:00Z --limit 200 -o text
```

## Idempotent migration pattern

```ruby
class AddFooToBars < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:bars, :foo)

    add_column :bars, :foo, :string
  end

  def down
    remove_column :bars, :foo if column_exists?(:bars, :foo)
  end
end
```

## GitHub ↔ Render

- Repo: `merouaneamqor/storebrief`
- Auto-deploy on push to `main`
- After merge wave: compare `origin/main` tip to the `live` deploy commit id
