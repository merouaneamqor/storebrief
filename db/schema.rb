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

ActiveRecord::Schema[8.1].define(version: 2025_09_27_120006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "communications", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "format", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "email"], name: "index_users_on_tenant_id_and_email", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  add_foreign_key "communications", "tenants"
  add_foreign_key "communications", "users", column: "author_id"
  add_foreign_key "deliveries", "communications"
  add_foreign_key "deliveries", "org_units"
  add_foreign_key "memberships", "org_units"
  add_foreign_key "memberships", "users"
  add_foreign_key "org_units", "org_units", column: "parent_id"
  add_foreign_key "org_units", "tenants"
  add_foreign_key "users", "tenants"
end
