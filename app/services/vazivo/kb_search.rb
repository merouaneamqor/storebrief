module Vazivo
  # Tenant-scoped full-text search over knowledge base articles.
  # Uses PostgreSQL FTS (tsvector + ts_rank) with role + optional store-tag access.
  class KbSearch
    Result = Struct.new(:articles, :query, :role, :store_tags, :published_only, keyword_init: true)

    def self.call(tenant:, query: nil, role: nil, store_tags: :auto, user: nil, published_only: true, bypass_access: false)
      new(
        tenant: tenant,
        query: query,
        role: role,
        store_tags: store_tags,
        user: user,
        published_only: published_only,
        bypass_access: bypass_access
      ).call
    end

    def initialize(tenant:, query: nil, role: nil, store_tags: :auto, user: nil, published_only: true, bypass_access: false)
      @tenant = tenant
      @query = query.to_s.strip
      @role = role.to_s.presence_in(Membership::ROLES)
      @store_tags = store_tags
      @user = user
      @published_only = published_only
      @bypass_access = bypass_access
    end

    def call
      scope = @tenant.kb_articles.includes(:kb_category, :author)
      scope = scope.published if @published_only
      scope = apply_access(scope)

      if @query.present?
        rank_sql = KbArticle.sanitize_sql_array([
          "kb_articles.*, ts_rank(kb_articles.search_vector, plainto_tsquery('simple', ?)) AS search_rank",
          @query
        ])
        scope = scope
          .where("kb_articles.search_vector @@ plainto_tsquery('simple', ?)", @query)
          .select(rank_sql)
          .order(Arel.sql("search_rank DESC, kb_articles.updated_at DESC, kb_articles.id DESC"))
      else
        scope = scope.ordered
      end

      Result.new(
        articles: scope,
        query: @query,
        role: @role,
        store_tags: normalized_store_tags_for_result,
        published_only: @published_only
      )
    end

    private

    def apply_access(scope)
      return scope if @bypass_access

      if @user.present? && @store_tags == :auto && @role.blank?
        return Vazivo::KbAccess.apply(scope, user: @user)
      end

      # Explicit role (e.g. HQ preview): role filter; store tags nil skips that dimension.
      tags = @store_tags == :auto ? nil : @store_tags
      Vazivo::KbAccess.apply(scope, role: @role, store_tags: tags, bypass: false)
    end

    def normalized_store_tags_for_result
      return [] if @store_tags == :auto || @store_tags.nil?

      Array(@store_tags).map { |t| t.to_s.strip }.reject(&:blank?).uniq
    end
  end
end
