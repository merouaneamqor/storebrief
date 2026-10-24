password = "password"
slug = "qa-vazivo"
tenant = Tenant.find_or_create_by!(slug: slug) do |t|
  t.name = "QA Vazivo"
  t.brand_name = "QA Vazivo"
  t.features = Tenant.default_features
  Tenant.default_palette.each { |k, v| t.public_send("#{k}=", v) }
end

OrgUnit.reset_column_information

region = tenant.org_units.find_or_create_by!(name: "QA Region", unit_type: "region")
area = tenant.org_units.find_or_create_by!(name: "QA Area Casa", unit_type: "area") do |u|
  u.parent = region
end
area.update!(parent: region) if area.parent_id != region.id

store = tenant.org_units.find_or_initialize_by(name: "QA Store Maarif", unit_type: "store")
store.parent = area
store.store_format = "supermarket" if store.respond_to?(:store_format=)
store.cluster_key = "casa-nord" if store.respond_to?(:cluster_key=)
store.save!

store2 = tenant.org_units.find_or_initialize_by(name: "QA Store Ain Diab", unit_type: "store")
store2.parent = area
store2.store_format = "express" if store2.respond_to?(:store_format=)
store2.cluster_key = "casa-sud" if store2.respond_to?(:cluster_key=)
store2.save!

def ensure_user!(tenant, email:, name:, org_unit:, role:, password:)
  user = tenant.users.find_or_initialize_by(email: email)
  user.name = name
  user.password = password
  user.password_confirmation = password
  user.locale = "fr"
  user.privacy_notice_accepted_at ||= Time.current
  user.save!
  user.memberships.find_or_create_by!(org_unit: org_unit, role: role)
  user
end

hq = ensure_user!(tenant, email: "hq@qa-vazivo.test", name: "QA HQ", org_unit: region, role: "hq", password: password)
area_u = ensure_user!(tenant, email: "area@qa-vazivo.test", name: "QA Area", org_unit: area, role: "area", password: password)
store_u = ensure_user!(tenant, email: "store@qa-vazivo.test", name: "QA Store", org_unit: store, role: "store", password: password)

Playbook.ensure_defaults!(tenant)

template = tenant.checklist_templates.find_or_create_by!(category: "opening", title_fr: "Ouverture QA") do |tpl|
  tpl.items = [
    { "type" => "question", "key" => "alarms", "title_fr" => "Alarmes", "required" => true },
    { "type" => "question", "key" => "vitrine", "title_fr" => "Vitrine", "required" => false, "requires_photo" => true }
  ]
end

unless tenant.communications.where(title_fr: "Tache QA vitrine").exists?
  brief = tenant.communications.create!(
    author: hq,
    title_fr: "Tache QA vitrine",
    body_fr: "Confirmez la vitrine promo.",
    format: "task",
    status: "draft",
    priority: "urgent"
  )
  brief.send_to!([ store.id, store2.id ])
end

Vazivo::Assignment.backfill!(tenant)

puts "QA tenant id=#{tenant.id} slug=#{tenant.slug}"
puts "units=#{tenant.org_units.pluck(:name, :unit_type).inspect}"
puts "users=#{tenant.users.pluck(:email).inspect}"
puts "HQ: hq@qa-vazivo.test / password"
puts "Area: area@qa-vazivo.test / password"
puts "Store: store@qa-vazivo.test / password"
puts "template=#{template.id} tasks=#{tenant.communications.where(format: 'task').count}"

# A second tenant makes browser offline-cache isolation reproducible.
offline_other = Tenant.find_or_create_by!(slug: "qa-offline-other") do |record|
  record.name = "QA Offline Other"
  record.brand_name = "QA Offline Other"
  record.features = Tenant.default_features
  Tenant.default_palette.each { |key, value| record.public_send("#{key}=", value) }
end
offline_store = offline_other.org_units.find_or_create_by!(name: "Offline Other Store", unit_type: "store")
ensure_user!(offline_other, email: "store@qa-offline-other.test", name: "Offline Other User", org_unit: offline_store, role: "store", password: password)
