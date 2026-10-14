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

ActiveRecord::Schema[8.1].define(version: 2026_10_15_120000) do
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
    t.bigint "assignee_id"
    t.datetime "due_at"
    t.integer "escalation_level", default: 0, null: false
    t.datetime "escalated_at"
    t.index ["assignee_id"], name: "index_checklist_deliveries_on_assignee_id"
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
    t.boolean "required", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
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
    t.date "campaign_on"
    t.bigint "playbook_id"
    t.jsonb "target_snapshot", default: {}, null: false
    t.date "starts_on"
    t.index ["author_id"], name: "index_checklists_on_author_id"
    t.index ["checklist_template_id"], name: "index_checklists_on_checklist_template_id"
    t.index ["playbook_id"], name: "index_checklists_on_playbook_id"
    t.index ["tenant_id", "status"], name: "index_checklists_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_checklists_on_tenant_id"
  end

  create_table "communication_questions", force: :cascade do |t|
    t.bigint "communication_id", null: false
    t.integer "position", default: 0, null: false
    t.string "question_type", default: "short_text", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.boolean "required", default: false, null: false
    t.jsonb "options", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["communication_id", "position"], name: "index_communication_questions_on_communication_id_and_position"
    t.index ["communication_id"], name: "index_communication_questions_on_communication_id"
  end

  create_table "communication_templates", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "body_fr", default: "", null: false
    t.text "body_ar"
    t.string "format", default: "task", null: false
    t.boolean "requires_proof", default: false, null: false
    t.string "priority", default: "routine", null: false
    t.jsonb "questions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "requires_approval", default: false, null: false
    t.index ["tenant_id", "title_fr"], name: "index_communication_templates_on_tenant_id_and_title_fr"
    t.index ["tenant_id"], name: "index_communication_templates_on_tenant_id"
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
    t.string "source", default: "compose", null: false
    t.boolean "requires_proof", default: false, null: false
    t.datetime "due_at"
    t.bigint "playbook_id"
    t.jsonb "recurrence_rule", default: {}, null: false
    t.date "recurrence_next_on"
    t.bigint "recurrence_parent_id"
    t.date "occurrence_on"
    t.string "priority", default: "routine", null: false
    t.bigint "communication_template_id"
    t.bigint "visit_id"
    t.bigint "source_delivery_id"
    t.bigint "source_checklist_item_response_id"
    t.bigint "depends_on_communication_id"
    t.boolean "requires_approval", default: false, null: false
    t.index ["author_id"], name: "index_communications_on_author_id"
    t.index ["communication_template_id"], name: "index_communications_on_communication_template_id"
    t.index ["depends_on_communication_id"], name: "index_communications_on_depends_on_communication_id"
    t.index ["playbook_id"], name: "index_communications_on_playbook_id"
    t.index ["recurrence_next_on"], name: "index_communications_on_recurrence_next_on", where: "(recurrence_next_on IS NOT NULL)"
    t.index ["recurrence_parent_id", "occurrence_on"], name: "index_communications_on_series_occurrence", unique: true, where: "(recurrence_parent_id IS NOT NULL)"
    t.index ["recurrence_parent_id"], name: "index_communications_on_recurrence_parent_id"
    t.index ["source_checklist_item_response_id"], name: "index_communications_on_source_checklist_item_response_id"
    t.index ["source_checklist_item_response_id"], name: "index_communications_unique_corrective_checklist_item", unique: true, where: "((source_checklist_item_response_id IS NOT NULL) AND ((source)::text = 'corrective'::text))"
    t.index ["source_delivery_id"], name: "index_communications_on_source_delivery_id"
    t.index ["source_delivery_id"], name: "index_communications_unique_corrective_source_delivery", unique: true, where: "((source_delivery_id IS NOT NULL) AND ((source)::text = 'corrective'::text))"
    t.index ["tenant_id", "status"], name: "index_communications_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_communications_on_tenant_id"
    t.index ["visit_id"], name: "index_communications_on_visit_id"
  end

  create_table "deliveries", force: :cascade do |t|
    t.bigint "communication_id", null: false
    t.bigint "org_unit_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "awareness", default: "pending", null: false
    t.bigint "assignee_id"
    t.datetime "due_at"
    t.integer "escalation_level", default: 0, null: false
    t.datetime "escalated_at"
    t.string "verdict"
    t.text "verdict_note"
    t.bigint "validated_by_id"
    t.datetime "validated_at"
    t.integer "score"
    t.datetime "dependency_cleared_at"
    t.bigint "dependency_cleared_by_id"
    t.index ["assignee_id"], name: "index_deliveries_on_assignee_id"
    t.index ["communication_id", "org_unit_id"], name: "index_deliveries_on_communication_id_and_org_unit_id", unique: true
    t.index ["communication_id"], name: "index_deliveries_on_communication_id"
    t.index ["dependency_cleared_by_id"], name: "index_deliveries_on_dependency_cleared_by_id"
    t.index ["org_unit_id"], name: "index_deliveries_on_org_unit_id"
    t.index ["score"], name: "index_deliveries_on_score"
    t.index ["validated_by_id"], name: "index_deliveries_on_validated_by_id"
  end

  create_table "delivery_answers", force: :cascade do |t|
    t.bigint "delivery_id", null: false
    t.bigint "communication_question_id", null: false
    t.jsonb "value", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["communication_question_id"], name: "index_delivery_answers_on_communication_question_id"
    t.index ["delivery_id", "communication_question_id"], name: "index_delivery_answers_on_delivery_and_question", unique: true
    t.index ["delivery_id"], name: "index_delivery_answers_on_delivery_id"
  end

  create_table "delivery_comments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "delivery_id", null: false
    t.bigint "user_id", null: false
    t.bigint "parent_id"
    t.text "body", null: false
    t.jsonb "mentioned_user_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["delivery_id", "created_at"], name: "index_delivery_comments_on_delivery_id_and_created_at"
    t.index ["delivery_id"], name: "index_delivery_comments_on_delivery_id"
    t.index ["parent_id", "created_at"], name: "index_delivery_comments_on_parent_id_and_created_at"
    t.index ["parent_id"], name: "index_delivery_comments_on_parent_id"
    t.index ["tenant_id", "created_at"], name: "index_delivery_comments_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_delivery_comments_on_tenant_id"
    t.index ["user_id"], name: "index_delivery_comments_on_user_id"
  end

  create_table "delivery_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "delivery_id", null: false
    t.bigint "actor_id"
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_delivery_events_on_actor_id"
    t.index ["delivery_id", "created_at"], name: "index_delivery_events_on_delivery_id_and_created_at"
    t.index ["delivery_id"], name: "index_delivery_events_on_delivery_id"
    t.index ["tenant_id", "created_at"], name: "index_delivery_events_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_delivery_events_on_tenant_id"
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
    t.datetime "privacy_consent_at"
    t.boolean "marketing_contact_consent", default: false, null: false
    t.index ["created_at"], name: "index_demo_requests_on_created_at"
  end

  create_table "escalation_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.integer "level", null: false
    t.string "notified_role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_escalation_events_on_subject"
    t.index ["tenant_id"], name: "index_escalation_events_on_tenant_id"
  end

  create_table "kb_article_versions", force: :cascade do |t|
    t.bigint "kb_article_id", null: false
    t.bigint "author_id"
    t.integer "version", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "body_fr", default: "", null: false
    t.text "body_ar"
    t.string "publish_state", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_kb_article_versions_on_author_id"
    t.index ["kb_article_id", "version"], name: "index_kb_article_versions_on_article_and_version", unique: true
    t.index ["kb_article_id"], name: "index_kb_article_versions_on_kb_article_id"
  end

  create_table "kb_articles", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "kb_category_id", null: false
    t.bigint "author_id"
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "body_fr", default: "", null: false
    t.text "body_ar"
    t.string "publish_state", default: "draft", null: false
    t.integer "version", default: 1, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_kb_articles_on_author_id"
    t.index ["kb_category_id"], name: "index_kb_articles_on_kb_category_id"
    t.index ["tenant_id", "kb_category_id"], name: "index_kb_articles_on_tenant_id_and_kb_category_id"
    t.index ["tenant_id", "publish_state"], name: "index_kb_articles_on_tenant_id_and_publish_state"
    t.index ["tenant_id", "title_fr"], name: "index_kb_articles_on_tenant_id_and_title_fr"
    t.index ["tenant_id"], name: "index_kb_articles_on_tenant_id"
  end

  create_table "kb_categories", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "parent_id"
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "description_fr"
    t.text "description_ar"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_kb_categories_on_parent_id"
    t.index ["tenant_id", "parent_id", "position"], name: "index_kb_categories_on_tenant_parent_position"
    t.index ["tenant_id", "title_fr"], name: "index_kb_categories_on_tenant_id_and_title_fr"
    t.index ["tenant_id"], name: "index_kb_categories_on_tenant_id"
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
    t.string "channel", default: "web_push", null: false
    t.string "phone"
    t.text "message", null: false
    t.string "status", default: "stubbed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "billed", default: false, null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notification_logs_on_notifiable_type_and_notifiable_id"
    t.index ["tenant_id"], name: "index_notification_logs_on_tenant_id"
    t.index ["user_id"], name: "index_notification_logs_on_user_id"
  end

  create_table "org_units", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "parent_id"
    t.string "name", null: false
    t.string "unit_type", null: false
    t.string "store_format"
    t.string "cluster_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_org_units_on_parent_id"
    t.index ["tenant_id", "cluster_key"], name: "index_org_units_on_tenant_id_and_cluster_key"
    t.index ["tenant_id", "store_format"], name: "index_org_units_on_tenant_id_and_store_format"
    t.index ["tenant_id", "unit_type"], name: "index_org_units_on_tenant_id_and_unit_type"
    t.index ["tenant_id"], name: "index_org_units_on_tenant_id"
  end

  create_table "playbooks", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "key", null: false
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "description_fr", null: false
    t.text "description_ar"
    t.jsonb "steps", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "key"], name: "index_playbooks_on_tenant_id_and_key", unique: true
    t.index ["tenant_id"], name: "index_playbooks_on_tenant_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "tenant_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["tenant_id"], name: "index_push_subscriptions_on_tenant_id"
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "tenant_mail_settings", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "from_email"
    t.string "from_name"
    t.string "smtp_address"
    t.integer "smtp_port", default: 587, null: false
    t.string "smtp_domain"
    t.string "smtp_username"
    t.string "smtp_password"
    t.string "smtp_authentication", default: "plain", null: false
    t.boolean "smtp_enable_starttls_auto", default: true, null: false
    t.boolean "use_platform", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_tenant_mail_settings_on_tenant_id", unique: true
  end

  create_table "tenant_saml_settings", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.boolean "enabled", default: false, null: false
    t.boolean "sso_enforced", default: false, null: false
    t.string "idp_entity_id"
    t.string "idp_sso_target_url"
    t.text "idp_cert"
    t.string "email_attribute"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_tenant_saml_settings_on_tenant_id", unique: true
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
    t.jsonb "features", default: {}, null: false
    t.boolean "ramadan_mode", default: false, null: false
    t.string "opens_at", default: "09:00", null: false
    t.string "closes_at", default: "21:00", null: false
    t.string "ramadan_opens_at", default: "12:00", null: false
    t.string "ramadan_closes_at", default: "01:00", null: false
    t.integer "corrective_deadline_days", default: 3, null: false
    t.jsonb "preferences", default: {}, null: false
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "fr", null: false
    t.string "whatsapp_phone"
    t.boolean "super_admin", default: false, null: false
    t.datetime "privacy_notice_accepted_at"
    t.boolean "operational_email_opt_out", default: false, null: false
    t.datetime "whatsapp_alerts_consent_at"
    t.datetime "push_alerts_consent_at"
    t.index ["email"], name: "index_users_on_super_admin_email", unique: true, where: "(super_admin = true)"
    t.index ["tenant_id", "email"], name: "index_users_on_tenant_id_and_email", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  create_table "visits", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "org_unit_id", null: false
    t.bigint "auditor_id", null: false
    t.bigint "created_by_id"
    t.datetime "planned_at", null: false
    t.string "status", default: "planned", null: false
    t.text "notes"
    t.text "cancel_reason"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditor_id"], name: "index_visits_on_auditor_id"
    t.index ["created_by_id"], name: "index_visits_on_created_by_id"
    t.index ["org_unit_id"], name: "index_visits_on_org_unit_id"
    t.index ["tenant_id", "planned_at"], name: "index_visits_on_tenant_id_and_planned_at"
    t.index ["tenant_id", "status"], name: "index_visits_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_visits_on_tenant_id"
  end

  create_table "vm_mission_targets", force: :cascade do |t|
    t.bigint "vm_mission_id", null: false
    t.bigint "org_unit_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["org_unit_id"], name: "index_vm_mission_targets_on_org_unit_id"
    t.index ["vm_mission_id", "org_unit_id"], name: "index_vm_mission_targets_on_mission_and_store", unique: true
    t.index ["vm_mission_id"], name: "index_vm_mission_targets_on_vm_mission_id"
  end

  create_table "vm_missions", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "created_by_id"
    t.string "title_fr", null: false
    t.string "title_ar"
    t.text "instructions_fr", null: false
    t.text "instructions_ar"
    t.date "deadline_on", null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_vm_missions_on_created_by_id"
    t.index ["tenant_id", "deadline_on"], name: "index_vm_missions_on_tenant_id_and_deadline_on"
    t.index ["tenant_id", "status"], name: "index_vm_missions_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_vm_missions_on_tenant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "checklist_deliveries", "checklists"
  add_foreign_key "checklist_deliveries", "org_units"
  add_foreign_key "checklist_deliveries", "users", column: "assignee_id"
  add_foreign_key "checklist_item_responses", "checklist_deliveries"
  add_foreign_key "checklist_item_responses", "checklist_items"
  add_foreign_key "checklist_items", "checklists"
  add_foreign_key "checklist_templates", "tenants"
  add_foreign_key "checklists", "checklist_templates"
  add_foreign_key "checklists", "playbooks", on_delete: :nullify
  add_foreign_key "checklists", "tenants"
  add_foreign_key "checklists", "users", column: "author_id"
  add_foreign_key "communication_questions", "communications"
  add_foreign_key "communication_templates", "tenants"
  add_foreign_key "communications", "checklist_item_responses", column: "source_checklist_item_response_id"
  add_foreign_key "communications", "communication_templates"
  add_foreign_key "communications", "communications", column: "depends_on_communication_id"
  add_foreign_key "communications", "communications", column: "recurrence_parent_id", on_delete: :nullify
  add_foreign_key "communications", "deliveries", column: "source_delivery_id"
  add_foreign_key "communications", "playbooks", on_delete: :nullify
  add_foreign_key "communications", "tenants"
  add_foreign_key "communications", "users", column: "author_id"
  add_foreign_key "communications", "visits"
  add_foreign_key "deliveries", "communications"
  add_foreign_key "deliveries", "org_units"
  add_foreign_key "deliveries", "users", column: "assignee_id"
  add_foreign_key "deliveries", "users", column: "dependency_cleared_by_id"
  add_foreign_key "deliveries", "users", column: "validated_by_id"
  add_foreign_key "delivery_answers", "communication_questions"
  add_foreign_key "delivery_answers", "deliveries"
  add_foreign_key "delivery_comments", "deliveries"
  add_foreign_key "delivery_comments", "delivery_comments", column: "parent_id"
  add_foreign_key "delivery_comments", "tenants"
  add_foreign_key "delivery_comments", "users"
  add_foreign_key "delivery_events", "deliveries"
  add_foreign_key "delivery_events", "tenants"
  add_foreign_key "delivery_events", "users", column: "actor_id"
  add_foreign_key "escalation_events", "tenants"
  add_foreign_key "kb_article_versions", "kb_articles"
  add_foreign_key "kb_article_versions", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "kb_articles", "kb_categories"
  add_foreign_key "kb_articles", "tenants"
  add_foreign_key "kb_articles", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "kb_categories", "kb_categories", column: "parent_id", on_delete: :nullify
  add_foreign_key "kb_categories", "tenants"
  add_foreign_key "memberships", "org_units"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_logs", "tenants"
  add_foreign_key "notification_logs", "users"
  add_foreign_key "org_units", "org_units", column: "parent_id"
  add_foreign_key "org_units", "tenants"
  add_foreign_key "playbooks", "tenants"
  add_foreign_key "push_subscriptions", "tenants"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "tenant_mail_settings", "tenants"
  add_foreign_key "tenant_saml_settings", "tenants"
  add_foreign_key "users", "tenants"
  add_foreign_key "visits", "org_units"
  add_foreign_key "visits", "tenants"
  add_foreign_key "visits", "users", column: "auditor_id"
  add_foreign_key "visits", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "vm_mission_targets", "org_units"
  add_foreign_key "vm_mission_targets", "vm_missions"
  add_foreign_key "vm_missions", "tenants"
  add_foreign_key "vm_missions", "users", column: "created_by_id", on_delete: :nullify
end
