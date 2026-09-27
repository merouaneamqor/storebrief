puts "Seeding StoreBrief (Morocco first release)..."

[
  ChecklistItemResponse,
  ChecklistDelivery,
  ChecklistItem,
  Checklist,
  ChecklistTemplate,
  NotificationLog,
  Delivery,
  Communication,
  Membership,
  User,
  OrgUnit,
  Tenant
].each(&:delete_all)

password = "password"

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

def build_tenant!(name:, slug:, password:, with_whatsapp: false)
  tenant = Tenant.create!(name: name, slug: slug)

  casablanca = tenant.org_units.create!(name: "Région Casablanca-Settat", unit_type: "region")
  rabat = tenant.org_units.create!(name: "Région Rabat-Salé", unit_type: "region")

  casa_area = tenant.org_units.create!(name: "Casa Centre", unit_type: "area", parent: casablanca)
  rabat_area = tenant.org_units.create!(name: "Agdal", unit_type: "area", parent: rabat)

  stores = [
    tenant.org_units.create!(name: "#{name.split.first} Maarif", unit_type: "store", parent: casa_area),
    tenant.org_units.create!(name: "#{name.split.first} Ain Diab", unit_type: "store", parent: casa_area),
    tenant.org_units.create!(name: "#{name.split.first} Agdal", unit_type: "store", parent: rabat_area)
  ]

  hq_user = tenant.users.create!(
    name: "#{name} HQ",
    email: "hq@#{slug}.test",
    password: password,
    password_confirmation: password,
    locale: "fr"
  )
  hq_user.memberships.create!(org_unit: casablanca, role: "hq")

  store_user = tenant.users.create!(
    name: "#{stores.first.name} Manager",
    email: "store@#{slug}.test",
    password: password,
    password_confirmation: password,
    locale: "ar",
    whatsapp_phone: with_whatsapp ? "+212612345678" : nil
  )
  store_user.memberships.create!(org_unit: stores.first, role: "store")

  seed_templates!(tenant)

  news = tenant.communications.create!(
    author: hq_user,
    title_fr: "Bienvenue sur StoreBrief",
    title_ar: "مرحباً بكم في StoreBrief",
    body_fr: "Brief d'accueil pour #{name}. Infos et tâches pour vos magasins.",
    body_ar: "رسالة ترحيب لـ #{name}. أخبار ومهام لمتاجركم.",
    format: "news",
    status: "draft"
  )
  news.send_to!([casablanca.id])

  task = tenant.communications.create!(
    author: hq_user,
    title_fr: "Contrôle vitrine promo",
    title_ar: "فحص واجهة العرض",
    body_fr: "Confirmez que la vitrine promo est installée, puis marquez la tâche terminée.",
    body_ar: "أكدوا تركيب واجهة العرض ثم ضعوا علامة مكتمل.",
    format: "task",
    status: "draft"
  )
  task.send_to!([stores.first.id, stores.second.id])

  opening = tenant.checklist_templates.find_by!(category: "opening")
  checklist = Checklist.build_from_template(opening, author: hq_user)
  checklist.save!
  checklist.send_to!([stores.first.id])

  tenant
end

build_tenant!(name: "Atlas Retail Maroc", slug: "atlas", password: password, with_whatsapp: true)
build_tenant!(name: "Contoso Shops", slug: "contoso", password: password, with_whatsapp: false)

puts "Seeded atlas + contoso (password: password). Store atlas user has WhatsApp stub phone."
