# frozen_string_literal: true

# Full sales-demo tenant used to pitch Vazivo.
# Idempotent: destroys and recreates the `nour` tenant only.
class SalesDemoSeeder
  SLUG = "nour"
  PASSWORD = "demo2026"
  PLATFORM_ADMIN_PASSWORD = "password"
  HQ_EMAIL = "hq@nour.test"
  STORE_EMAIL = "store@nour.test"
  ADMIN_EMAIL = "admin@vazivo.test"

  TEMPLATE_DEFS = [
    {
      category: "opening",
      title_fr: "Ouverture magasin",
      title_ar: "افتتاح المتجر",
      description_fr: "Contrôles d'ouverture avant l'accueil des clients.",
      description_ar: "فحوصات الافتتاح قبل استقبال الزبناء.",
      items: [
        { title_fr: "Alarmes désactivées", title_ar: "إيقاف الإنذار", requires_photo: false },
        { title_fr: "Éclairage et caisse OK", title_ar: "الإضاءة والصندوق جاهزان", requires_photo: false },
        { title_fr: "Photo de la vitrine", title_ar: "صورة الواجهة", requires_photo: true }
      ]
    },
    {
      category: "closing",
      title_fr: "Fermeture magasin",
      title_ar: "إغلاق المتجر",
      description_fr: "Checklist de fermeture et sécurisation.",
      description_ar: "قائمة التحقق للإغلاق والتأمين.",
      items: [
        { title_fr: "Caisse clôturée", title_ar: "إقفال الصندوق", requires_photo: false },
        { title_fr: "Portes verrouillées", title_ar: "إغلاق الأبواب", requires_photo: false },
        { title_fr: "Photo alarme armée", title_ar: "صورة تفعيل الإنذار", requires_photo: true }
      ]
    },
    {
      category: "cleanliness",
      title_fr: "Propreté magasin",
      title_ar: "نظافة المتجر",
      description_fr: "Standards d'hygiène et propreté.",
      description_ar: "معايير النظافة.",
      items: [
        { title_fr: "Sols propres", title_ar: "الأرضية نظيفة", requires_photo: false },
        { title_fr: "Rayons rangés", title_ar: "الرفوف مرتبة", requires_photo: true }
      ]
    },
    {
      category: "safety",
      title_fr: "Sécurité",
      title_ar: "السلامة",
      description_fr: "Contrôles sécurité incendie et issues.",
      description_ar: "فحوصات السلامة ومخارج الطوارئ.",
      items: [
        { title_fr: "Extincteurs accessibles", title_ar: "طفايات الحريق متاحة", requires_photo: true },
        { title_fr: "Issues dégagées", title_ar: "المخارج خالية", requires_photo: false }
      ]
    },
    {
      category: "promotions",
      title_fr: "Mise en avant promo",
      title_ar: "عرض ترويجي",
      description_fr: "Vérifier la conformité visuelle des promotions.",
      description_ar: "التحقق من العرض الترويجي.",
      items: [
        { title_fr: "PLV en place", title_ar: "اللوحات في مكانها", requires_photo: true },
        { title_fr: "Prix affichés", title_ar: "الأسعار ظاهرة", requires_photo: false }
      ]
    },
    {
      category: "equipment",
      title_fr: "Incident équipement",
      title_ar: "عطل معدات",
      description_fr: "Signaler un équipement défaillant avec photo.",
      description_ar: "الإبلاغ عن عطل مع صورة.",
      items: [
        { title_fr: "Décrire le problème", title_ar: "وصف المشكل", requires_photo: false },
        { title_fr: "Photo de l'équipement", title_ar: "صورة المعدات", requires_photo: true }
      ]
    },
    {
      category: "store_visit",
      title_fr: "Visite magasin",
      title_ar: "زيارة المتجر",
      description_fr: "Grille de visite manager / région.",
      description_ar: "شبكة زيارة المدير / المنطقة.",
      items: [
        { title_fr: "Accueil clients", title_ar: "استقبال الزبناء", requires_photo: false },
        { title_fr: "Merchandising", title_ar: "عرض المنتجات", requires_photo: true },
        { title_fr: "Stock arrière", title_ar: "مخزون المستودع", requires_photo: false }
      ]
    }
  ].freeze

  PALETTE = {
    brand_color: "#0f766e",
    primary_deep_color: "#115e59",
    primary_soft_color: "#ccfbf1",
    secondary_color: "#d97706",
    secondary_soft_color: "#fef3c7",
    text_color: "#134e4a",
    text_muted_color: "#5b716e",
    bg_color: "#f0fdfa",
    bg_deep_color: "#ccfbf1",
    surface_color: "#ffffff",
    line_color: "#99f6e4",
    sidebar_color: "#042f2e",
    sidebar_text_color: "#ccfbf1",
    warn_color: "#9a3412",
    warn_soft_color: "#ffedd5"
  }.freeze

  def self.seed!(password: PASSWORD)
    new(password: password).seed!
  end

  def initialize(password: PASSWORD)
    @password = password
  end

  def seed!
    saved_push = snapshot_push_subscriptions!
    wipe_existing!
    tenant = create_tenant!
    attach_brand_assets!(tenant)
    units = create_org_tree!(tenant)
    users = create_users!(tenant, units)
    restore_push_subscriptions!(tenant, users, saved_push)
    seed_templates!(tenant)
    seed_briefs!(tenant, users, units)
    seed_checklists!(tenant, users, units)
    tenant
  end

  private

  attr_reader :password

  def snapshot_push_subscriptions!
    existing = Tenant.find_by(slug: SLUG)
    return [] unless existing

    existing.push_subscriptions.includes(:user).map do |sub|
      {
        email: sub.user&.email,
        endpoint: sub.endpoint,
        p256dh: sub.p256dh,
        auth: sub.auth,
        user_agent: sub.user_agent
      }
    end.select { |row| row[:email].present? && row[:endpoint].present? }
  end

  def restore_push_subscriptions!(tenant, users, saved)
    return if saved.blank?

    by_email = {
      HQ_EMAIL => users[:hq],
      STORE_EMAIL => users[:store],
      "anfa@nour.test" => users[:anfa],
      "hassan@nour.test" => users[:hassan]
    }

    saved.each do |row|
      user = by_email[row[:email]]
      next unless user

      subscription = PushSubscription.find_or_initialize_by(endpoint: row[:endpoint])
      subscription.assign_attributes(
        user: user,
        tenant: tenant,
        p256dh: row[:p256dh],
        auth: row[:auth],
        user_agent: row[:user_agent]
      )
      subscription.save!
    end
  end

  def wipe_existing!
    existing = Tenant.find_by(slug: SLUG)
    return unless existing

    communication_ids = existing.communications.pluck(:id)
    checklist_ids = existing.checklists.pluck(:id)
    org_unit_ids = existing.org_units.pluck(:id)
    user_ids = existing.users.pluck(:id)

    if communication_ids.any?
      DeliveryAnswer.joins(:communication_question)
                    .where(communication_questions: { communication_id: communication_ids })
                    .delete_all
      CommunicationQuestion.where(communication_id: communication_ids).delete_all
      Delivery.where(communication_id: communication_ids).delete_all
    end

    if checklist_ids.any?
      ChecklistItemResponse.joins(:checklist_delivery)
                           .where(checklist_deliveries: { checklist_id: checklist_ids })
                           .delete_all
      ChecklistDelivery.where(checklist_id: checklist_ids).delete_all
      ChecklistItem.where(checklist_id: checklist_ids).delete_all
    end

    existing.notification_logs.delete_all
    existing.push_subscriptions.delete_all
    existing.checklists.delete_all
    existing.communications.delete_all
    existing.checklist_templates.delete_all
    Membership.where(user_id: user_ids).delete_all if user_ids.any?
    existing.users.delete_all
    existing.org_units.delete_all
    existing.logo.purge if existing.logo.attached?
    existing.logo_mark.purge if existing.logo_mark.attached?
    existing.favicon.purge if existing.favicon.attached?
    existing.delete
  end

  def create_tenant!
    Tenant.create!(
      name: "Nour Markets",
      slug: SLUG,
      brand_name: "Nour",
      tagline: "Chaque magasin, chaque matin",
      **Tenant.default_palette(**PALETTE)
    )
  end

  def attach_brand_assets!(tenant)
    dir = Rails.root.join("db/seeds/brand")
    {
      logo: "nour-logo.svg",
      logo_mark: "nour-mark.svg",
      favicon: "nour-favicon.svg"
    }.each do |name, filename|
      path = dir.join(filename)
      next unless path.exist?

      tenant.public_send(name).attach(
        io: File.open(path),
        filename: filename,
        content_type: "image/svg+xml"
      )
    end
  end

  def create_org_tree!(tenant)
    casa = tenant.org_units.create!(name: "Région Casablanca-Settat", unit_type: "region")
    rabat = tenant.org_units.create!(name: "Région Rabat-Salé", unit_type: "region")
    marrakech = tenant.org_units.create!(name: "Région Marrakech-Safi", unit_type: "region")

    casa_centre = tenant.org_units.create!(name: "Casa Centre", unit_type: "area", parent: casa)
    ain_sebaa = tenant.org_units.create!(name: "Aïn Sebaâ", unit_type: "area", parent: casa)
    agdal = tenant.org_units.create!(name: "Agdal-Hassan", unit_type: "area", parent: rabat)
    gueliz = tenant.org_units.create!(name: "Guéliz", unit_type: "area", parent: marrakech)

    stores = [
      tenant.org_units.create!(name: "Nour Maarif", unit_type: "store", parent: casa_centre),
      tenant.org_units.create!(name: "Nour Anfa", unit_type: "store", parent: casa_centre),
      tenant.org_units.create!(name: "Nour Aïn Sebaâ", unit_type: "store", parent: ain_sebaa),
      tenant.org_units.create!(name: "Nour Agdal", unit_type: "store", parent: agdal),
      tenant.org_units.create!(name: "Nour Hassan", unit_type: "store", parent: agdal),
      tenant.org_units.create!(name: "Nour Guéliz", unit_type: "store", parent: gueliz)
    ]

    {
      regions: [ casa, rabat, marrakech ],
      areas: [ casa_centre, ain_sebaa, agdal, gueliz ],
      stores: stores,
      flagship: stores.first
    }
  end

  def create_users!(tenant, units)
    hq = tenant.users.create!(
      name: "Sara Benali · Siège",
      email: HQ_EMAIL,
      password: password,
      password_confirmation: password,
      locale: "fr"
    )
    hq.memberships.create!(org_unit: units[:regions].first, role: "hq")

    store = tenant.users.create!(
      name: "Youssef Amrani · Maarif",
      email: STORE_EMAIL,
      password: password,
      password_confirmation: password,
      locale: "ar",
      whatsapp_phone: "+212661234567"
    )
    store.memberships.create!(org_unit: units[:flagship], role: "store")

    anfa = tenant.users.create!(
      name: "Imane Tazi · Anfa",
      email: "anfa@nour.test",
      password: password,
      password_confirmation: password,
      locale: "fr",
      whatsapp_phone: "+212662345678"
    )
    anfa.memberships.create!(org_unit: units[:stores].second, role: "store")

    hassan = tenant.users.create!(
      name: "Karim Bennani · Hassan",
      email: "hassan@nour.test",
      password: password,
      password_confirmation: password,
      locale: "fr",
      whatsapp_phone: "+212663456789"
    )
    hassan.memberships.create!(org_unit: units[:stores][4], role: "store")

    User.super_admins.where(email: ADMIN_EMAIL).find_each(&:destroy)
    admin = tenant.users.create!(
      name: "Vazivo Admin",
      email: ADMIN_EMAIL,
      password: PLATFORM_ADMIN_PASSWORD,
      password_confirmation: PLATFORM_ADMIN_PASSWORD,
      locale: "fr",
      super_admin: true
    )

    { hq: hq, store: store, anfa: anfa, hassan: hassan, admin: admin }
  end

  def seed_templates!(tenant)
    TEMPLATE_DEFS.each do |defn|
      tenant.checklist_templates.create!(
        category: defn[:category],
        title_fr: defn[:title_fr],
        title_ar: defn[:title_ar],
        description_fr: defn[:description_fr],
        description_ar: defn[:description_ar],
        items: defn[:items]
      )
    end
  end

  def seed_briefs!(tenant, users, units)
    hq = users[:hq]
    stores = units[:stores]

    news = tenant.communications.create!(
      author: hq,
      title_fr: "Lancement promo Ramadan, semaine 1",
      title_ar: "إطلاق عرض رمضان، الأسبوع 1",
      body_fr: "Priorité siège : déployer la PLV dates & lait dans tous les magasins avant 10h. Photos obligatoires sur le brief tâche.",
      body_ar: "أولوية المقر: تثبيت لوحات التمر والحليب قبل العاشرة. الصور مطلوبة في مهمة العرض.",
      format: "news",
      status: "draft"
    )
    news.send_to!(units[:regions].map(&:id))
    news.deliveries.limit(3).each(&:mark_read!)

    task = tenant.communications.create!(
      author: hq,
      title_fr: "Contrôle vitrine promo dates",
      title_ar: "فحص واجهة عرض التمر",
      body_fr: "Répondez aux questions et joignez une photo de la vitrine.",
      body_ar: "أجيبوا على الأسئلة وأرفقوا صورة الواجهة.",
      format: "task",
      status: "draft"
    )
    task.communication_questions.create!(
      position: 0,
      title_fr: "La PLV dates est-elle installée selon le planogramme ?",
      title_ar: "هل لوحة التمر مثبتة حسب المخطط؟",
      question_type: "single_choice",
      required: true,
      options: [
        { "label_fr" => "Oui, conforme", "label_ar" => "نعم، مطابق" },
        { "label_fr" => "Partiel", "label_ar" => "جزئي" },
        { "label_fr" => "Non installé", "label_ar" => "غير مثبت" }
      ]
    )
    task.communication_questions.create!(
      position: 1,
      title_fr: "Photo de la vitrine (face)",
      title_ar: "صورة الواجهة (أمامية)",
      question_type: "image",
      required: true
    )
    task.communication_questions.create!(
      position: 2,
      title_fr: "Commentaire magasin",
      title_ar: "ملاحظة المتجر",
      question_type: "short_text",
      required: false
    )
    task.send_to!(stores.first(4).map(&:id))

    # Flagship store answered the choices (image left pending so demo can finish it)
    delivery = task.deliveries.find_by!(org_unit: units[:flagship])
    q_choice, _q_image, q_text = task.communication_questions.ordered.to_a
    delivery.delivery_answers.create!(
      communication_question: q_choice,
      value: { "text" => "Oui, conforme" }
    )
    delivery.delivery_answers.create!(
      communication_question: q_text,
      value: { "text" => "PLV reçue hier, installée ce matin." }
    )

    follow_up = tenant.communications.create!(
      author: hq,
      title_fr: "Rappel froid: relevé températures",
      title_ar: "تذكير التبريد: قياس الحرارة",
      body_fr: "Relevez les températures des meubles frais avant 12h et signalez tout écart >2°C.",
      body_ar: "سجّلوا حرارة الثلاجات قبل الظهر وأبلغوا عن أي انحراف فوق درجتين.",
      format: "task",
      status: "draft"
    )
    follow_up.send_to!([ stores[2].id, stores[3].id, stores[5].id ])
  end

  def seed_checklists!(tenant, users, units)
    hq = users[:hq]
    stores = units[:stores]

    opening = tenant.checklist_templates.find_by!(category: "opening")
    opening_run = Checklist.build_from_template(opening, author: hq)
    opening_run.save!
    opening_run.send_to!(stores.first(3).map(&:id))

    # Complete opening for flagship (skip photo items for seed simplicity)
    flagship_delivery = opening_run.checklist_deliveries.find_by!(org_unit: units[:flagship])
    opening_run.checklist_items.each do |item|
      next if item.requires_photo?

      flagship_delivery.checklist_item_responses.create!(
        checklist_item: item,
        completed: true
      )
    end

    promo = tenant.checklist_templates.find_by!(category: "promotions")
    promo_run = Checklist.build_from_template(promo, author: hq)
    promo_run.save!
    promo_run.send_to!(stores.map(&:id))

    cleanliness = tenant.checklist_templates.find_by!(category: "cleanliness")
    clean_run = Checklist.build_from_template(cleanliness, author: hq)
    clean_run.save!
    # Maarif + Anfa — both have demo store users (and often a subscribed device).
    clean_run.send_to!([ stores[0].id, stores[1].id ])
  end
end
