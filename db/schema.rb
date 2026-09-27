# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_27_133417) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "checklist_deliveries", force: :cascade do |t|
    t.bigint "checklist_id", null: false
    t.bigint "org_unit_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.string "client_uuid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_id", "org_unit_id"], name: "index_checklist_deliveries_on_checklist_id_and_org_unit_id", unique: true
    t.index ["checklist_id"], name: "index_checklist_deliveries_on_checklist_id"
    t.index ["client_uuid"], name: "index_checklist_deliveries_on_client_uuid", unique: true, where: "(client_uuid IS NOT NULL)"
    t.index ["org_unit_id"], name: "index_checklist_deliveries_on_org_unit_id"
  end

  create_table "checklist_item_responses", force: :cascade do |t|
    t.bigint "checklist_delivery_id", null: false
    t.bigint "checklist_item_id", null: false
    t.boolean "completed", default: false, null: false
    t.text "notes"
    t.string "client_uuid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_delivery_id", "checklist_item_id"], name: "index_item_responses_on_delivery_and_item", unique: true
    t.index ["checklist_delivery_id"], name: "index_checklist_item_responses_on_checklist_delivery_id"
    t.index ["checklist_item_id"], name: "index_checklist_item_responses_on_checklist_item_id"
    t.index ["client_uuid"], name: "index_checklist_item_responses_on_client_uuid", unique: true, where: "(client_uuid IS NOT NULL)"
  end

  create_table "checklist_items", force: :cascade do |t|
    t.bigint "checklist_id", null: false
    t.integer "position", default: 0, null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.boolean "requires_photo", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_id"], name: "index_checklist_items_on_checklist_id"
  end

  create_table "checklist_templates", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "category", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "description_fr"
    t.text "description_ar"
    t.jsonb "items", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "category"], name: "index_checklist_templates_on_tenant_id_and_category"
    t.index ["tenant_id"], name: "index_checklist_templates_on_tenant_id"
  end

  create_table "checklists", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "author_id", null: false
    t.bigint "checklist_template_id"
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "description_fr"
    t.text "description_ar"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_checklists_on_author_id"
    t.index ["checklist_template_id"], name: "index_checklists_on_checklist_template_id"
    t.index ["tenant_id", "status"], name: "index_checklists_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_checklists_on_tenant_id"
  end

  create_table "communications", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "author_id", null: false
    t.string "format", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "body_fr", null: false
    t.text "body_ar"
    t.index ["author_id"], name: "index_communications_on_author_id"
    t.index ["tenant_id", "status"], name: "index_communications_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_communications_on_tenant_id"
  end

  create_table "deliveries", force: :cascade do |t|
    t.bigint "communication_id", null: false
    t.bigint "org_unit_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["communication_id", "org_unit_id"], name: "index_deliveries_on_communication_id_and_org_unit_id", unique: true
    t.index ["communication_id"], name: "index_deliveries_on_communication_id"
    t.index ["org_unit_id"], name: "index_deliveries_on_org_unit_id"
  end

  create_table "demo_requests", force: :cascade do |t|
    t.string "name", null: false
    t.string "company", null: false
    t.string "email"
    t.string "phone"
    t.integer "store_count"
    t.string "preferred_locale", default: "fr", null: false
    t.string "status", default: "new", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_demo_requests_on_created_at"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "org_unit_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["org_unit_id"], name: "index_memberships_on_org_unit_id"
    t.index ["user_id", "org_unit_id"], name: "index_memberships_on_user_id_and_org_unit_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notification_logs", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id"
    t.string "notifiable_type", null: false
    t.bigint "notifiable_id", null: false
    t.string "channel", default: "whatsapp", null: false
    t.string "phone"
    t.text "message", null: false
    t.string "status", default: "stubbed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notification_logs_on_notifiable_type_and_notifiable_id"
    t.index ["tenant_id"], name: "index_notification_logs_on_tenant_id"
    t.index ["user_id"], name: "index_notification_logs_on_user_id"
  end

  create_table "org_units", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "parent_id"
    t.string "name", null: false
    t.string "unit_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_org_units_on_parent_id"
    t.index ["tenant_id", "unit_type"], name: "index_org_units_on_tenant_id_and_unit_type"
    t.index ["tenant_id"], name: "index_org_units_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "brand_color"
    t.string "secondary_color", default: "#1e4b7a", null: false
    t.string "primary_deep_color", default: "#084c3f", null: false
    t.string "primary_soft_color", default: "#d7efe7", null: false
    t.string "secondary_soft_color", default: "#e0ecf8", null: false
    t.string "text_color", default: "#102033", null: false
    t.string "text_muted_color", default: "#5c6d7c", null: false
    t.string "bg_color", default: "#f4f1ea", null: false
    t.string "bg_deep_color", default: "#efeae2", null: false
    t.string "surface_color", default: "#fffcf7", null: false
    t.string "line_color", default: "#ddd6cb", null: false
    t.string "sidebar_color", default: "#0f172a", null: false
    t.string "sidebar_text_color", default: "#e2e8f0", null: false
    t.string "warn_color", default: "#9a3412", null: false
    t.string "warn_soft_color", default: "#ffedd5", null: false
    t.string "brand_name"
    t.string "tagline"
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "fr", null: false
    t.string "whatsapp_phone"
    t.index ["tenant_id", "email"], name: "index_users_on_tenant_id_and_email", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "checklist_deliveries", "checklists"
  add_foreign_key "checklist_deliveries", "org_units"
  add_foreign_key "checklist_item_responses", "checklist_deliveries"
  add_foreign_key "checklist_item_responses", "checklist_items"
  add_foreign_key "checklist_items", "checklists"
  add_foreign_key "checklist_templates", "tenants"
  add_foreign_key "checklists", "checklist_templates"
  add_foreign_key "checklists", "tenants"
  add_foreign_key "checklists", "users", column: "author_id"
  add_foreign_key "communications", "tenants"
  add_foreign_key "communications", "users", column: "author_id"
  add_foreign_key "deliveries", "communications"
  add_foreign_key "deliveries", "org_units"
  add_foreign_key "memberships", "org_units"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_logs", "tenants"
  add_foreign_key "notification_logs", "users"
  add_foreign_key "org_units", "org_units", column: "parent_id"
  add_foreign_key "org_units", "tenants"
  add_foreign_key "users", "tenants"
end
