class Playbook < ApplicationRecord
  include Bilingual

  SYSTEM_KEYS = %w[aid sale black_friday].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,47}\z/

  belongs_to :tenant
  has_many :communications, dependent: :nullify
  has_many :checklists, dependent: :nullify

  validates :key, presence: true, format: { with: KEY_FORMAT }, uniqueness: { scope: :tenant_id }
  validates :title_fr, :description_fr, presence: true
  validate :steps_must_be_valid

  bilingual_fields :title, :description

  def step_list
    Array(steps).map(&:with_indifferent_access)
  end

  def system?
    SYSTEM_KEYS.include?(key)
  end

  def custom?
    !system?
  end

  def self.ensure_defaults!(tenant)
    DEFAULTS.each do |defn|
      tenant.playbooks.find_or_create_by!(key: defn[:key]) do |playbook|
        playbook.assign_attributes(defn.except(:key))
      end
    end
    tenant.playbooks.order(:key)
  end

  def reset_to_default!
    raise ArgumentError, "only system playbooks can be reset" unless system?

    defn = DEFAULTS.find { |row| row[:key] == key }
    update!(defn.except(:key))
  end

  def self.assign_unique_key!(tenant, title)
    base = title.to_s.parameterize(separator: "_").presence || "playbook"
    base = base.gsub(/[^a-z0-9_]/, "")[0, 40]
    base = "playbook" if base.blank? || base !~ /\A[a-z]/
    candidate = base
    index = 2
    while tenant.playbooks.exists?(key: candidate)
      candidate = "#{base}_#{index}"
      index += 1
    end
    candidate
  end

  def self.normalize_steps(raw)
    Array(raw).filter_map do |step|
      step = step.to_h.with_indifferent_access
      title_fr = step[:title_fr].to_s.strip
      next if title_fr.blank?

      photo = step[:requires_photo]
      photo = photo.last if photo.is_a?(Array)

      {
        "offset_days" => step[:offset_days].to_i,
        "title_fr" => title_fr,
        "title_ar" => step[:title_ar].to_s.strip.presence,
        "requires_photo" => ActiveModel::Type::Boolean.new.cast(photo)
      }
    end
  end

  DEFAULTS = [
    {
      key: "aid",
      title_fr: "Playbook Aïd",
      title_ar: "دليل العيد",
      description_fr: "La même préparation Aïd, du stock jusqu'à l'audit, déployée sur tout le réseau.",
      description_ar: "نفس تحضير العيد، من المخزون إلى التدقيق، يُنشر على كل المتاجر.",
      steps: [
        { "offset_days" => -14, "title_fr" => "Contrôle de stock", "title_ar" => "فحص المخزون", "requires_photo" => false },
        { "offset_days" => -10, "title_fr" => "Préparation VM", "title_ar" => "تحضير العرض البصري", "requires_photo" => false },
        { "offset_days" => -7, "title_fr" => "Briefing équipe", "title_ar" => "إحاطة الفريق", "requires_photo" => false },
        { "offset_days" => -5, "title_fr" => "Supports PLV", "title_ar" => "مواد العرض", "requires_photo" => true },
        { "offset_days" => -3, "title_fr" => "Installation vitrine", "title_ar" => "تركيب الواجهة", "requires_photo" => true },
        { "offset_days" => -1, "title_fr" => "Validation photo", "title_ar" => "التحقق من الصورة", "requires_photo" => true },
        { "offset_days" => 0, "title_fr" => "Audit final", "title_ar" => "التدقيق النهائي", "requires_photo" => true }
      ]
    },
    {
      key: "sale",
      title_fr: "Playbook Soldes",
      title_ar: "دليل التخفيضات",
      description_fr: "Le déploiement soldes : prix, signalétique, vitrine, puis photo de conformité.",
      description_ar: "إطلاق التخفيضات: الأسعار، اللافتات، الواجهة، ثم صورة المطابقة.",
      steps: [
        { "offset_days" => -7, "title_fr" => "Contrôle des prix", "title_ar" => "مراجعة الأسعار", "requires_photo" => false },
        { "offset_days" => -3, "title_fr" => "Signalétique soldes", "title_ar" => "لافتات التخفيضات", "requires_photo" => true },
        { "offset_days" => -1, "title_fr" => "Vitrine soldes", "title_ar" => "واجهة التخفيضات", "requires_photo" => true },
        { "offset_days" => 0, "title_fr" => "Photo d'ouverture", "title_ar" => "صورة يوم الإطلاق", "requires_photo" => true }
      ]
    },
    {
      key: "black_friday",
      title_fr: "Playbook Black Friday",
      title_ar: "دليل الجمعة البيضاء",
      description_fr: "Campagne Black Friday : stock clé, briefing, PLV, vitrine, et photo le jour J.",
      description_ar: "حملة الجمعة البيضاء: المخزون الأساسي، الإحاطة، مواد العرض، الواجهة، وصورة يوم الإطلاق.",
      steps: [
        { "offset_days" => -10, "title_fr" => "Stock des best-sellers", "title_ar" => "مخزون الأكثر مبيعاً", "requires_photo" => false },
        { "offset_days" => -5, "title_fr" => "Briefing équipe", "title_ar" => "إحاطة الفريق", "requires_photo" => false },
        { "offset_days" => -2, "title_fr" => "PLV et prix", "title_ar" => "مواد العرض والأسعار", "requires_photo" => true },
        { "offset_days" => 0, "title_fr" => "Vitrine et photo", "title_ar" => "الواجهة والصورة", "requires_photo" => true }
      ]
    }
  ].freeze

  private

  def steps_must_be_valid
    list = step_list
    if list.empty?
      errors.add(:steps, :blank)
      return
    end

    if list.any? { |step| step[:title_fr].to_s.strip.blank? }
      errors.add(:steps, :invalid)
    end
  end
end
