puts "Seeding StoreBrief..."

Delivery.delete_all
Communication.delete_all
Membership.delete_all
User.delete_all
OrgUnit.delete_all
Tenant.delete_all

password = "password"

def build_tenant!(name:, slug:, password:)
  tenant = Tenant.create!(name: name, slug: slug)

  north = tenant.org_units.create!(name: "North Region", unit_type: "region")
  south = tenant.org_units.create!(name: "South Region", unit_type: "region")

  north_area = tenant.org_units.create!(name: "North Metro", unit_type: "area", parent: north)
  south_area = tenant.org_units.create!(name: "South Coast", unit_type: "area", parent: south)

  stores = [
    tenant.org_units.create!(name: "#{name.split.first} Central", unit_type: "store", parent: north_area),
    tenant.org_units.create!(name: "#{name.split.first} Riverside", unit_type: "store", parent: north_area),
    tenant.org_units.create!(name: "#{name.split.first} Harbour", unit_type: "store", parent: south_area)
  ]

  hq_user = tenant.users.create!(
    name: "#{name} HQ",
    email: "hq@#{slug}.test",
    password: password,
    password_confirmation: password
  )
  hq_user.memberships.create!(org_unit: north, role: "hq")

  store_user = tenant.users.create!(
    name: "#{stores.first.name} Manager",
    email: "store@#{slug}.test",
    password: password,
    password_confirmation: password
  )
  store_user.memberships.create!(org_unit: stores.first, role: "store")

  news = tenant.communications.create!(
    author: hq_user,
    title: "Welcome to StoreBrief",
    body: "This is a news brief for #{name}. Share updates with selected stores across the hierarchy.",
    format: "news",
    status: "draft"
  )
  news.send_to!([north.id])

  task = tenant.communications.create!(
    author: hq_user,
    title: "Window display check",
    body: "Confirm the seasonal window display is set correctly and mark this task complete when done.",
    format: "task",
    status: "draft"
  )
  task.send_to!([stores.first.id, stores.second.id])

  tenant
end

build_tenant!(name: "Northwind Retail", slug: "northwind", password: password)
build_tenant!(name: "Contoso Shops", slug: "contoso", password: password)

puts "Seeded tenants: northwind, contoso (password: password)"
