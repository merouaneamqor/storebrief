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

ActiveRecord::Schema[8.1].define(version: 2026_10_23_070000) do
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

  create_table "approval_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.bigint "actor_id"
    t.string "kind", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_approval_events_on_actor_id"
    t.index ["subject_type", "subject_id"], name: "index_approval_events_on_subject"
    t.index ["tenant_id"], name: "index_approval_events_on_tenant_id"
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
    t.string "verdict"
    t.text "verdict_note"
    t.bigint "validated_by_id"
    t.datetime "validated_at"
    t.index ["assignee_id"], name: "index_checklist_deliveries_on_assignee_id"
    t.index ["checklist_id", "org_unit_id"], name: "index_checklist_deliveries_on_checklist_id_and_org_unit_id", unique: true
    t.index ["checklist_id"], name: "index_checklist_deliveries_on_checklist_id"
    t.index ["client_uuid"], name: "index_checklist_deliveries_on_client_uuid", unique: true, where: "(client_uuid IS NOT NULL)"
    t.index ["org_unit_id"], name: "index_checklist_deliveries_on_org_unit_id"
    t.index ["validated_by_id"], name: "index_checklist_deliveries_on_validated_by_id"
  end

  create_table "checklist_delivery_comments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "checklist_delivery_id", null: false
    t.bigint "user_id", null: false
    t.bigint "parent_id"
    t.text "body", null: false
    t.jsonb "mentioned_user_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_delivery_id"], name: "index_checklist_delivery_comments_on_checklist_delivery_id"
    t.index ["parent_id"], name: "index_checklist_delivery_comments_on_parent_id"
    t.index ["tenant_id"], name: "index_checklist_delivery_comments_on_tenant_id"
    t.index ["user_id"], name: "index_checklist_delivery_comments_on_user_id"
  end

  create_table "checklist_delivery_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "checklist_delivery_id", null: false
    t.bigint "actor_id"
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_checklist_delivery_events_on_actor_id"
    t.index ["checklist_delivery_id"], name: "index_checklist_delivery_events_on_checklist_delivery_id"
    t.index ["tenant_id"], name: "index_checklist_delivery_events_on_tenant_id"
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
    t.decimal "weight", precision: 8, scale: 2, default: "1.0", null: false
    t.index ["communication_id", "position"], name: "index_communication_questions_on_communication_id_and_position"
    t.index ["communication_id"], name: "index_communication_questions_on_communication_id"
    t.check_constraint "weight > 0::numeric", name: "communication_questions_positive_weight"
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
    t.string "review_status"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "review_note"
    t.boolean "critical_broadcast", default: false, null: false
    t.boolean "requires_acknowledgement", default: false, null: false
    t.boolean "broadcast_email", default: false, null: false
    t.boolean "broadcast_whatsapp", default: false, null: false
    t.index ["author_id"], name: "index_communications_on_author_id"
    t.index ["communication_template_id"], name: "index_communications_on_communication_template_id"
    t.index ["depends_on_communication_id"], name: "index_communications_on_depends_on_communication_id"
    t.index ["playbook_id"], name: "index_communications_on_playbook_id"
    t.index ["recurrence_next_on"], name: "index_communications_on_recurrence_next_on", where: "(recurrence_next_on IS NOT NULL)"
    t.index ["recurrence_parent_id", "occurrence_on"], name: "index_communications_on_series_occurrence", unique: true, where: "(recurrence_parent_id IS NOT NULL)"
    t.index ["recurrence_parent_id"], name: "index_communications_on_recurrence_parent_id"
    t.index ["reviewed_by_id"], name: "index_communications_on_reviewed_by_id"
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
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_id"
    t.index ["acknowledged_by_id"], name: "index_deliveries_on_acknowledged_by_id"
    t.index ["assignee_id"], name: "index_deliveries_on_assignee_id"
    t.index ["communication_id", "org_unit_id"], name: "index_deliveries_on_communication_id_and_org_unit_id", unique: true
    t.index ["communication_id"], name: "index_deliveries_on_communication_id"
    t.index ["dependency_cleared_by_id"], name: "index_deliveries_on_dependency_cleared_by_id"
    t.index ["org_unit_id"], name: "index_deliveries_on_org_unit_id"
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

  create_table "delivery_reads", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "delivery_id", null: false
    t.bigint "user_id", null: false
    t.datetime "read_at", null: false
    t.datetime "created_at", null: false
    t.index ["delivery_id", "user_id"], name: "index_delivery_reads_on_delivery_id_and_user_id", unique: true
    t.index ["delivery_id"], name: "index_delivery_reads_on_delivery_id"
    t.index ["tenant_id", "read_at"], name: "index_delivery_reads_on_tenant_id_and_read_at"
    t.index ["tenant_id"], name: "index_delivery_reads_on_tenant_id"
    t.index ["user_id"], name: "index_delivery_reads_on_user_id"
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
    t.string "country"
    t.string "requested_plan"
    t.text "requirements"
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

  create_table "export_logs", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "actor_id"
    t.string "source", null: false
    t.string "output_format", null: false
    t.jsonb "filters", default: {}, null: false
    t.integer "row_count", null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_export_logs_on_actor_id"
    t.index ["tenant_id", "created_at"], name: "index_export_logs_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_export_logs_on_tenant_id"
  end

  create_table "feed_comments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.text "body", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_feed_comments_on_subject"
    t.index ["tenant_id"], name: "index_feed_comments_on_tenant_id"
    t.index ["user_id"], name: "index_feed_comments_on_user_id"
  end

  create_table "feed_posts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "org_unit_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["org_unit_id"], name: "index_feed_posts_on_org_unit_id"
    t.index ["tenant_id"], name: "index_feed_posts_on_tenant_id"
    t.index ["user_id"], name: "index_feed_posts_on_user_id"
  end

  create_table "feed_reactions", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "kind", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id", "user_id"], name: "idx_on_subject_type_subject_id_user_id_e9ef93422a", unique: true
    t.index ["subject_type", "subject_id"], name: "index_feed_reactions_on_subject"
    t.index ["tenant_id"], name: "index_feed_reactions_on_tenant_id"
    t.index ["user_id"], name: "index_feed_reactions_on_user_id"
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
    t.string "audience_roles", default: [], null: false, array: true
    t.tsvector "search_vector"
    t.string "audience_store_tags", default: [], null: false, array: true
    t.index ["audience_roles"], name: "index_kb_articles_on_audience_roles", using: :gin
    t.index ["audience_store_tags"], name: "index_kb_articles_on_audience_store_tags", using: :gin
    t.index ["author_id"], name: "index_kb_articles_on_author_id"
    t.index ["kb_category_id"], name: "index_kb_articles_on_kb_category_id"
    t.index ["search_vector"], name: "index_kb_articles_on_search_vector", using: :gin
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
    t.bigint "tenant_role_id"
    t.index ["org_unit_id"], name: "index_memberships_on_org_unit_id"
    t.index ["tenant_role_id"], name: "index_memberships_on_tenant_role_id"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "store_format"
    t.string "cluster_key"
    t.index ["parent_id"], name: "index_org_units_on_parent_id"
    t.index ["tenant_id", "cluster_key"], name: "index_org_units_on_tenant_id_and_cluster_key"
    t.index ["tenant_id", "store_format"], name: "index_org_units_on_tenant_id_and_store_format"
    t.index ["tenant_id", "unit_type"], name: "index_org_units_on_tenant_id_and_unit_type"
    t.index ["tenant_id"], name: "index_org_units_on_tenant_id"
  end

  create_table "playbook_deploy_requests", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "playbook_id", null: false
    t.bigint "author_id", null: false
    t.bigint "reviewed_by_id"
    t.bigint "communication_id"
    t.jsonb "deploy_params", default: {}, null: false
    t.string "review_status", default: "pending_review", null: false
    t.datetime "reviewed_at"
    t.text "review_note"
    t.datetime "deployed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_playbook_deploy_requests_on_author_id"
    t.index ["communication_id"], name: "index_playbook_deploy_requests_on_communication_id"
    t.index ["playbook_id"], name: "index_playbook_deploy_requests_on_playbook_id"
    t.index ["reviewed_by_id"], name: "index_playbook_deploy_requests_on_reviewed_by_id"
    t.index ["tenant_id"], name: "index_playbook_deploy_requests_on_tenant_id"
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

  create_table "pricing_audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "action", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.jsonb "changes_made", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_pricing_audit_logs_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_pricing_audit_logs_on_user_id"
  end

  create_table "pricing_plan_versions", force: :cascade do |t|
    t.bigint "pricing_plan_id", null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.string "currency", null: false
    t.boolean "active_for_sales", null: false
    t.bigint "changed_by_id"
    t.datetime "created_at", null: false
    t.index ["changed_by_id"], name: "index_pricing_plan_versions_on_changed_by_id"
    t.index ["pricing_plan_id"], name: "index_pricing_plan_versions_on_pricing_plan_id"
  end

  create_table "pricing_plans", force: :cascade do |t|
    t.string "key", null: false
    t.integer "position", default: 0, null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.string "currency", default: "MAD", null: false
    t.boolean "active_for_sales", default: true, null: false
    t.integer "max_stores"
    t.decimal "max_discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.jsonb "volume_tiers", default: [], null: false
    t.jsonb "limits", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_pricing_plans_on_key", unique: true
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

  create_table "quotations", force: :cascade do |t|
    t.string "reference", null: false
    t.bigint "pricing_plan_id", null: false
    t.string "customer_name", null: false
    t.string "customer_email"
    t.integer "store_count", null: false
    t.decimal "unit_price", precision: 10, scale: 2, null: false
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.string "currency", default: "MAD", null: false
    t.text "terms"
    t.date "valid_until"
    t.string "status", default: "draft", null: false
    t.datetime "issued_at"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_quotations_on_created_by_id"
    t.index ["pricing_plan_id"], name: "index_quotations_on_pricing_plan_id"
    t.index ["reference"], name: "index_quotations_on_reference", unique: true
    t.index ["status"], name: "index_quotations_on_status"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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

  create_table "tenant_roles", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.string "base_role", null: false
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_tenant_roles_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_tenant_roles_on_tenant_id"
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
    t.string "status", default: "pending", null: false
    t.string "verdict"
    t.text "verdict_note"
    t.datetime "submitted_at"
    t.datetime "validated_at"
    t.bigint "validated_by_id"
    t.index ["org_unit_id"], name: "index_vm_mission_targets_on_org_unit_id"
    t.index ["validated_by_id"], name: "index_vm_mission_targets_on_validated_by_id"
    t.index ["vm_mission_id", "org_unit_id"], name: "index_vm_mission_targets_on_mission_and_store", unique: true
    t.index ["vm_mission_id", "status"], name: "index_vm_mission_targets_on_vm_mission_id_and_status"
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
    t.string "version_label"
    t.index ["created_by_id"], name: "index_vm_missions_on_created_by_id"
    t.index ["tenant_id", "deadline_on"], name: "index_vm_missions_on_tenant_id_and_deadline_on"
    t.index ["tenant_id", "status"], name: "index_vm_missions_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_vm_missions_on_tenant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "approval_events", "tenants"
  add_foreign_key "approval_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "checklist_deliveries", "checklists"
  add_foreign_key "checklist_deliveries", "org_units"
  add_foreign_key "checklist_deliveries", "users", column: "assignee_id"
  add_foreign_key "checklist_deliveries", "users", column: "validated_by_id"
  add_foreign_key "checklist_delivery_comments", "checklist_deliveries"
  add_foreign_key "checklist_delivery_comments", "checklist_delivery_comments", column: "parent_id"
  add_foreign_key "checklist_delivery_comments", "tenants"
  add_foreign_key "checklist_delivery_comments", "users"
  add_foreign_key "checklist_delivery_events", "checklist_deliveries"
  add_foreign_key "checklist_delivery_events", "tenants"
  add_foreign_key "checklist_delivery_events", "users", column: "actor_id"
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
  add_foreign_key "communications", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "communications", "visits"
  add_foreign_key "deliveries", "communications"
  add_foreign_key "deliveries", "org_units"
  add_foreign_key "deliveries", "users", column: "acknowledged_by_id"
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
  add_foreign_key "delivery_reads", "deliveries"
  add_foreign_key "delivery_reads", "tenants"
  add_foreign_key "delivery_reads", "users"
  add_foreign_key "escalation_events", "tenants"
  add_foreign_key "export_logs", "tenants"
  add_foreign_key "export_logs", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "feed_comments", "tenants"
  add_foreign_key "feed_comments", "users"
  add_foreign_key "feed_posts", "org_units"
  add_foreign_key "feed_posts", "tenants"
  add_foreign_key "feed_posts", "users"
  add_foreign_key "feed_reactions", "tenants"
  add_foreign_key "feed_reactions", "users"
  add_foreign_key "kb_article_versions", "kb_articles"
  add_foreign_key "kb_article_versions", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "kb_articles", "kb_categories"
  add_foreign_key "kb_articles", "tenants"
  add_foreign_key "kb_articles", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "kb_categories", "kb_categories", column: "parent_id", on_delete: :nullify
  add_foreign_key "kb_categories", "tenants"
  add_foreign_key "memberships", "org_units"
  add_foreign_key "memberships", "tenant_roles"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_logs", "tenants"
  add_foreign_key "notification_logs", "users"
  add_foreign_key "org_units", "org_units", column: "parent_id"
  add_foreign_key "org_units", "tenants"
  add_foreign_key "playbook_deploy_requests", "communications", on_delete: :nullify
  add_foreign_key "playbook_deploy_requests", "playbooks"
  add_foreign_key "playbook_deploy_requests", "tenants"
  add_foreign_key "playbook_deploy_requests", "users", column: "author_id"
  add_foreign_key "playbook_deploy_requests", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "playbooks", "tenants"
  add_foreign_key "pricing_audit_logs", "users"
  add_foreign_key "pricing_plan_versions", "pricing_plans"
  add_foreign_key "pricing_plan_versions", "users", column: "changed_by_id"
  add_foreign_key "push_subscriptions", "tenants"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "quotations", "pricing_plans"
  add_foreign_key "quotations", "users", column: "created_by_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tenant_mail_settings", "tenants"
  add_foreign_key "tenant_roles", "tenants"
  add_foreign_key "tenant_saml_settings", "tenants"
  add_foreign_key "users", "tenants"
  add_foreign_key "visits", "org_units"
  add_foreign_key "visits", "tenants"
  add_foreign_key "visits", "users", column: "auditor_id"
  add_foreign_key "visits", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "vm_mission_targets", "org_units"
  add_foreign_key "vm_mission_targets", "users", column: "validated_by_id", on_delete: :nullify
  add_foreign_key "vm_mission_targets", "vm_missions"
  add_foreign_key "vm_missions", "tenants"
  add_foreign_key "vm_missions", "users", column: "created_by_id", on_delete: :nullify
end
