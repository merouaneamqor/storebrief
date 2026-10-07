class Tenant < ApplicationRecord
  HEX_COLOR = /\A#[0-9A-Fa-f]{6}\z/
  IMAGE_TYPES = %w[image/png image/jpeg image/jpg image/webp image/svg+xml image/x-icon image/vnd.microsoft.icon].freeze

  FEATURE_FLAGS = {
    saml_sso: {
      label: "SAML SSO",
      hint: "Allow single sign-on on this brand’s subdomain (configure IdP under SSO).",
      default: false
    },
    briefs: {
      label: "Briefs",
      hint: "HQ can compose and send news/task briefs.",
      default: true
    },
    checklists: {
      label: "Checklists",
      hint: "HQ checklists, templates, and store checklist inbox.",
      default: true
    },
    reports: {
      label: "Reports",
      hint: "HQ reports dashboard.",
      default: true
    },
    whatsapp_alerts: {
      label: "WhatsApp alerts",
      hint: "Optional WhatsApp stubs alongside push and email. Not the primary channel.",
      default: false
    },
    push_alerts: {
      label: "Push notifications",
      hint: "Primary store alerts via the Vazivo PWA (web push).",
      default: true
    },
    email_alerts: {
      label: "Email alerts",
      hint: "Email store users on new briefs/checklists. Uses tenant SMTP, or Vazivo SMTP (billed).",
      default: true
    },
    offline_checklists: {
      label: "Offline checklists",
      hint: "Store offline queue + sync chip for checklist responses.",
      default: true
    },
    morocco_ops: {
      label: "Morocco operations",
      hint: "Store acknowledgement, Ramadan hours, campaign playbooks, coaching verdicts, and the morning radar.",
      default: true
    }
  }.freeze

  HOUR_OF_DAY = /\A([01]\d|2[0-3]):[0-5]\d\z/

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

  has_one :saml_setting, class_name: "TenantSamlSetting", dependent: :destroy, inverse_of: :tenant
  has_one :mail_setting, class_name: "TenantMailSetting", dependent: :destroy, inverse_of: :tenant
  accepts_nested_attributes_for :saml_setting
  accepts_nested_attributes_for :mail_setting

  has_many :escalation_events, dependent: :destroy
  has_many :checklists, dependent: :destroy
  has_many :communications, dependent: :destroy
  has_many :playbooks, dependent: :destroy
  has_many :visits, dependent: :destroy
  has_many :audit_templates, dependent: :destroy
  has_many :checklist_templates, dependent: :destroy
  has_many :notification_logs, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :org_units, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-]+\z/ }
  validates :brand_name, presence: true, length: { maximum: 60 }
  validates :tagline, length: { maximum: 120 }, allow_blank: true
  validates :opens_at, :closes_at, :ramadan_opens_at, :ramadan_closes_at, format: { with: HOUR_OF_DAY }

  BRAND_COLORS.each_key do |attr|
    validates attr, presence: true, format: { with: HEX_COLOR }
  end

  validate :acceptable_brand_assets

  before_validation :normalize_brand_colors
  before_validation :normalize_features
  before_validation :apply_hour_defaults
  after_save :purge_removed_brand_assets

  FEATURE_FLAGS.each_key do |key|
    define_method("feature_#{key}") { feature?(key) }
    define_method("feature_#{key}=") do |value|
      self.features = feature_hash.merge(key.to_s => ActiveModel::Type::Boolean.new.cast(value))
    end
  end

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

  def feature?(key)
    key = key.to_sym
    meta = FEATURE_FLAGS.fetch(key)
    raw = feature_hash[key.to_s]
    return meta[:default] if raw.nil?

    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def feature_hash
    value = features
    value.is_a?(Hash) ? value.stringify_keys : {}
  end

  def saml_sso_enabled?
    feature?(:saml_sso) && saml_setting&.ready?
  end

  def saml_sso_enforced?
    saml_sso_enabled? && saml_setting.sso_enforced?
  end

  def saml_setting_or_build
    saml_setting || build_saml_setting
  end

  def mail_setting_or_build
    mail_setting || build_mail_setting(use_platform: true)
  end

  def email_delivery_mode
    mail_setting_or_build.delivery_mode
  end

  def effective_open
    ramadan_mode? ? ramadan_opens_at : opens_at
  end

  def effective_close
    ramadan_mode? ? ramadan_closes_at : closes_at
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

  def self.default_features
    FEATURE_FLAGS.transform_values { |meta| meta[:default] }.transform_keys(&:to_s)
  end

  private

  def apply_hour_defaults
    self.opens_at = "09:00" if opens_at.blank?
    self.closes_at = "21:00" if closes_at.blank?
    self.ramadan_opens_at = "12:00" if ramadan_opens_at.blank?
    self.ramadan_closes_at = "01:00" if ramadan_closes_at.blank?
  end

  def normalize_features
    self.features = feature_hash.slice(*FEATURE_FLAGS.keys.map(&:to_s))
  end

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
