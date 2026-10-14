module Vazivo
  # Chronological company news + announcements for one store.
  # No social chrome: read-only list that deep-links into the inbox item.
  class Newsfeed
    PER_PAGE = 20
    MAX_PER_PAGE = 50
    FORMATS = %w[news announcement].freeze

    Page = Struct.new(
      :deliveries, :page, :per_page, :total_count, :total_pages,
      keyword_init: true
    )

    def self.for(store:, tenant:, page: 1, per_page: PER_PAGE)
      new(store, tenant).page(page, per_page)
    end

    def initialize(store, tenant)
      @store = store
      @tenant = tenant
    end

    def page(page, per_page = PER_PAGE)
      per_page = normalize_per_page(per_page)
      page = [ page.to_i, 1 ].max
      scope = base_scope
      total = scope.count
      total_pages = [ (total.to_f / per_page).ceil, 1 ].max
      page = [ page, total_pages ].min

      Page.new(
        deliveries: scope.offset((page - 1) * per_page).limit(per_page).to_a,
        page: page,
        per_page: per_page,
        total_count: total,
        total_pages: total_pages
      )
    end

    private

    def base_scope
      Delivery.joins(:communication)
              .where(
                org_unit_id: @store.id,
                communications: {
                  tenant_id: @tenant.id,
                  status: "sent",
                  format: FORMATS
                }
              )
              .includes(:delivery_reads, communication: { attachments_attachments: :blob })
              .order(Arel.sql("communications.created_at DESC, deliveries.id DESC"))
    end

    def normalize_per_page(value)
      n = value.to_i
      n = PER_PAGE if n < 1
      [ n, MAX_PER_PAGE ].min
    end
  end
end
