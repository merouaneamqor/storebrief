# Brand assets (logo / mark / favicon) are rendered in <img> and <link rel="icon">.
# Rails serves SVG as application/octet-stream + attachment by default, which browsers
# refuse to display inline. Allow trusted tenant brand SVGs to be served as images.
Rails.application.config.active_storage.content_types_to_serve_as_binary -= ["image/svg+xml"]
Rails.application.config.active_storage.content_types_allowed_inline += ["image/svg+xml"]

# ActiveAdmin + Ransack require explicit allowlists on Active Storage models
# (they do not inherit ApplicationRecord's ransackable_* helpers).
Rails.application.config.to_prepare do
  ActiveStorage::Attachment.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[blob_id created_at id id_value name record_id record_type]
    end

    def self.ransackable_associations(_auth_object = nil)
      %w[blob record]
    end
  end

  ActiveStorage::Blob.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[byte_size checksum content_type created_at filename id key metadata service_name]
    end

    def self.ransackable_associations(_auth_object = nil)
      %w[attachments variant_records]
    end
  end
end
