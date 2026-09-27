# frozen_string_literal: true

ActiveAdmin.register ChecklistTemplate do
  menu priority: 6, label: "Checklist templates"

  permit_params :category, :title_fr, :title_ar, :description_fr, :description_ar, :items_json

  controller do
    def scoped_collection
      super.where(tenant_id: acting_tenant.id)
    end

    def build_new_resource
      super.tap { |r| r.tenant = acting_tenant }
    end

    def create
      build_resource
      apply_items_json
      create!
    end

    def update
      apply_items_json
      update!
    end

    private

    def apply_items_json
      raw = params.dig(:checklist_template, :items_json)
      return if raw.nil?

      resource.items = raw.blank? ? [] : JSON.parse(raw)
    rescue JSON::ParserError
      resource.errors.add(:items, "must be valid JSON")
    end
  end

  index do
    selectable_column
    id_column
    column :title_fr
    column :category
    column("Items") { |t| t.item_defs.size }
    column :created_at
    actions
  end

  filter :title_fr
  filter :category, as: :select, collection: ChecklistTemplate::CATEGORIES

  form do |f|
    f.inputs do
      f.input :category, as: :select, collection: ChecklistTemplate::CATEGORIES
      f.input :title_fr
      f.input :title_ar
      f.input :description_fr, as: :text
      f.input :description_ar, as: :text
      f.input :items_json,
              as: :text,
              label: "Items (JSON)",
              input_html: {
                value: f.object.items.present? ? JSON.pretty_generate(f.object.items) : "[]",
                rows: 12,
                name: "checklist_template[items_json]"
              },
              hint: 'JSON array, e.g. [{"title_fr":"Open doors","title_ar":"","requires_photo":false}]'
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :category
      row :title_fr
      row :title_ar
      row :description_fr
      row :description_ar
      row :items do |t|
        pre JSON.pretty_generate(t.items)
      end
      row :created_at
      row :updated_at
    end
  end
end
