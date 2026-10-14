module Vazivo
  # Role + optional store-tag access rules for knowledge base articles.
  #
  # Rules (empty allow-lists mean unrestricted for that dimension):
  # - audience_roles empty → any role; otherwise role must be listed
  # - audience_store_tags empty → any store; otherwise viewer store tags must overlap
  # - HQ management bypasses both filters; store/area readers are filtered
  # - Area managers use the union of tags from stores they manage
  class KbAccess
    Context = Struct.new(:role, :store_tags, :bypass, keyword_init: true)

    def self.context_for(user)
      new.context_for(user)
    end

    def self.store_tags_for(org_unit)
      new.store_tags_for(org_unit)
    end

    def self.allowed?(article, user: nil, role: nil, store_tags: nil, bypass: false)
      new.allowed?(article, user: user, role: role, store_tags: store_tags, bypass: bypass)
    end

    def self.apply(scope, user: nil, role: nil, store_tags: nil, bypass: false)
      new.apply(scope, user: user, role: role, store_tags: store_tags, bypass: bypass)
    end

    def context_for(user)
      return Context.new(role: nil, store_tags: [], bypass: true) if user.blank?
      return Context.new(role: "hq", store_tags: [], bypass: true) if user.super_admin? || user.hq?

      if user.area?
        area = user.area_org_unit
        stores = area ? area.descendant_stores.to_a : []
        tags = stores.flat_map { |store| store_tags_for(store) }.uniq.sort
        return Context.new(role: "area", store_tags: tags, bypass: false)
      end

      if user.store?
        store = user.store_org_unit
        return Context.new(role: "store", store_tags: store_tags_for(store), bypass: false)
      end

      Context.new(role: nil, store_tags: [], bypass: false)
    end

    def store_tags_for(org_unit)
      return [] if org_unit.blank?

      [ org_unit.store_format, org_unit.cluster_key ].map { |v| v.to_s.strip }.reject(&:blank?).uniq
    end

    def allowed?(article, user: nil, role: nil, store_tags: nil, bypass: false)
      ctx = resolve_context(user: user, role: role, store_tags: store_tags, bypass: bypass)
      return true if ctx.bypass

      article.accessible_to?(role: ctx.role, store_tags: ctx.store_tags)
    end

    def apply(scope, user: nil, role: nil, store_tags: nil, bypass: false)
      ctx = resolve_context(user: user, role: role, store_tags: store_tags, bypass: bypass)
      return scope if ctx.bypass

      scope.visible_to_access(role: ctx.role, store_tags: ctx.store_tags)
    end

    private

    def resolve_context(user:, role:, store_tags:, bypass:)
      if user.present? && role.nil? && store_tags.nil? && bypass == false
        return context_for(user)
      end

      # nil store_tags means "skip store-tag filter" (HQ role preview).
      # [] means viewer has no tags → only unrestricted articles.
      normalized =
        if store_tags.nil?
          nil
        else
          normalize_tags(store_tags)
        end

      Context.new(
        role: role.to_s.presence_in(Membership::ROLES),
        store_tags: normalized,
        bypass: bypass
      )
    end

    def normalize_tags(tags)
      Array(tags).map { |t| t.to_s.strip }.reject(&:blank?).uniq
    end
  end
end
