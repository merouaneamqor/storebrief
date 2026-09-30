# Shared builders for tenants, org trees, users, and sign-in.
module TenantHelpers
  TEST_VAPID_PUBLIC_KEY = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx".freeze
  TEST_VAPID_PRIVATE_KEY = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx".freeze

  Brand = Struct.new(:tenant, :region, :store, :hq, :store_user)

  def create_tenant(name, slug, **attrs)
    Tenant.create!(
      name: name,
      slug: slug,
      brand_name: name.split.first,
      **Tenant.default_palette,
      **attrs
    )
  end

  def create_user(tenant, org_unit:, role:, email: nil, locale: "en", **attrs)
    user = tenant.users.create!(
      name: role.to_s.upcase,
      email: email || "#{role}@#{tenant.slug}.test",
      password: "password",
      password_confirmation: "password",
      locale: locale,
      **attrs
    )
    user.memberships.create!(org_unit: org_unit, role: role.to_s)
    user
  end

  # Tenant with region → store, an HQ user on the region, and a store user on the store.
  def build_brand(slug, features: {}, store_locale: "en", **store_attrs)
    tenant = create_tenant(slug.titleize, slug, features: Tenant.default_features.merge(features.stringify_keys))
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    hq = create_user(tenant, org_unit: region, role: :hq)
    store_user = create_user(tenant, org_unit: store, role: :store, locale: store_locale, **store_attrs)
    Brand.new(tenant, region, store, hq, store_user)
  end

  def sign_in(user, tenant = user.tenant)
    post login_path, params: { tenant_slug: tenant.slug, email: user.email, password: "password" }
    follow_redirect!
  end

  def with_vapid
    ENV["VAPID_PUBLIC_KEY"] = TEST_VAPID_PUBLIC_KEY
    ENV["VAPID_PRIVATE_KEY"] = TEST_VAPID_PRIVATE_KEY
    yield
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end
end
