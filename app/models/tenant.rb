class Tenant < ApplicationRecord
  HEX_COLOR = /\A#[0-9A-Fa-f]{6}\z/
  IMAGE_TYPES = %w[image/png image/jpeg image/jpg image/webp image/svg+xml image/x-icon image/vnd.microsoft.icon].freeze

  BRAND_COLORS = {
    brand_color: { css: "--accent", label: "Primary", group: "Brand", default: "#0c6b58" },
    primary_deep_color: { css: "--accent-deep", label: "Primary deep", group: "Brand", default: "#084c3f" },
    primary_soft_color: { css: "--accent-soft", label: "Primary soft", group: "Brand", default: "#d7efe7" },
    secondary_color: { css: "--secondary", label: "Secondary", group: "Brand", default: "#1e4b7a" },
    secondary_soft_color: { css: "--secondary-soft", label: "Secondary soft", group: "Brand", default: "#e0ecf8" },
    text_color: { css: "--ink", label: "Text", group: "Text & surfaces", default: "#102033" },
    text_muted_color: { css: "--muted", label: "Text muted", group: "Text & surfaces", default: "#5c6d7c" },
    bg_color: { css: "--bg", label: "Background", group: "Text & surfaces", default: "#f4f1ea" },
    bg_deep_color: { css: "--bg-deep", label: "Background deep", group: "Text & surfaces", default: "#efeae2" },
    surface_color: { css: "--surface", label: "Surface / cards", group: "Text & surfaces", default: "#fffcf7" },
    line_color: { css: "--line", label: "Borders", group: "Text & surfaces", default: "#ddd6cb" },
    sidebar_color: { css: "--sidebar-bg", label: "Sidebar", group: "App shell", default: "#0f172a" },
    sidebar_text_color: { css: "--sidebar-text", label: "Sidebar text", group: "App shell", default: "#e2e8f0" },
    warn_color: { css: "--warn", label: "Warning", group: "Status", default: "#9a3412" },
    warn_soft_color: { css: "--warn-soft", label: "Warning soft", group: "Status", default: "#ffedd5" }
  }.freeze

  BRAND_ASSETS = {
    logo: { label: "Logo (wordmark)", hint: "Shown in the sidebar. PNG, JPG, WebP or SVG. Max ~160×48." },
    logo_mark: { label: "Logo mark", hint: "Small square icon when no wordmark is set." },
    favicon: { label: "Favicon", hint: "Browser tab icon. PNG, SVG or ICO." }
  }.freeze

  has_one_attached :logo
  has_one_attached :logo_mark
  has_one_attached :favicon

  attr_accessor :remove_logo, :remove_logo_mark, :remove_favicon

  has_many :checklists, dependent: :destroy
  has_many :communications, dependent: :destroy
  has_many :checklist_templates, dependent: :destroy
  has_many :notification_logs, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :org_units, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-]+\z/ }
  validates :brand_name, presence: true, length: { maximum: 60 }
  validates :tagline, length: { maximum: 120 }, allow_blank: true

  BRAND_COLORS.each_key do |attr|
    validates attr, presence: true, format: { with: HEX_COLOR }
  end

  validate :acceptable_brand_assets

  before_validation :normalize_brand_colors
  after_save :purge_removed_brand_assets

  def brand_css_variables
    vars = { "--brand" => brand_color }
    BRAND_COLORS.each do |attr, meta|
      vars[meta[:css]] = public_send(attr)
    end
    vars
  end

  def brand_style_attribute
    brand_css_variables.map { |k, v| "#{k}: #{v}" }.join("; ")
  end

  def display_brand_name
    brand_name.presence || name
  end

  def brand_color_deep
    primary_deep_color
  end

  def brand_color_soft
    primary_soft_color
  end

  def self.default_palette(**overrides)
    BRAND_COLORS.transform_values { |meta| meta[:default] }.merge(overrides)
  end

  private

  def normalize_brand_colors
    BRAND_COLORS.each_key do |attr|
      value = public_send(attr)
      next if value.blank?

      public_send("#{attr}=", "##{value.delete_prefix('#').downcase}")
    end
  end

  def acceptable_brand_assets
    BRAND_ASSETS.each_key do |name|
      file = public_send(name)
      next unless file.attached?
      next unless file.blob

      unless IMAGE_TYPES.include?(file.content_type)
        errors.add(name, "must be an image (PNG, JPG, WebP, SVG, or ICO)")
      end

      if file.byte_size.to_i > 2.megabytes
        errors.add(name, "is too large (max 2 MB)")
      end
    end
  end

  def purge_removed_brand_assets
    logo.purge_later if ActiveModel::Type::Boolean.new.cast(remove_logo)
    logo_mark.purge_later if ActiveModel::Type::Boolean.new.cast(remove_logo_mark)
    favicon.purge_later if ActiveModel::Type::Boolean.new.cast(remove_favicon)
  end
end
