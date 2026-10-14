module Vazivo
  # Tenant-scoped full-text search over knowledge base articles.
  # Uses PostgreSQL FTS (tsvector + ts_rank) with optional audience role filter.
  class KbSearch
    Result = Struct.new(:articles, :query, :role, :published_only, keyword_init: true)

    def self.call(tenant:, query: nil, role: nil, published_only: true)
      new(tenant: tenant, query: query, role: role, published_only: published_only).call
    end

    def initialize(tenant:, query: nil, role: nil, published_only: true)
      @tenant = tenant
      @query = query.to_s.strip
      @role = role.to_s.presence_in(Membership::ROLES)
      @published_only = published_only
    end

    def call
      scope = @tenant.kb_articles.includes(:kb_category, :author)
      scope = scope.published if @published_only
      scope = scope.visible_to_role(@role) if @role

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

      Result.new(articles: scope, query: @query, role: @role, published_only: @published_only)
    end
  end
end
