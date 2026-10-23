require "csv"

module Vazivo
  # Store audit history and region comparison from scored deliveries.
  # Audits are tenant-scoped deliveries that carry a score (and usually a verdict).
  class AuditHistory
    Entry = Struct.new(
      :delivery, :store, :title, :score, :verdict, :completed_at, :validated_at, :visit_id,
      keyword_init: true
    )
    StoreRow = Struct.new(
      :store, :audits, :avg_score, :last_score, :last_verdict, :last_at,
      :conforme, :improve, :non_conforme,
      keyword_init: true
    )
    RegionRow = Struct.new(
      :region, :stores, :audits, :avg_score, :conforme, :improve, :non_conforme,
      keyword_init: true
    )
    Result = Struct.new(:entries, :store_rows, :region_rows, :store, :region, keyword_init: true)

    def self.for(tenant, store_ids: nil, store: nil, region: nil, limit: 100)
      new(tenant, store_ids: store_ids, store: store, region: region, limit: limit).call
    end

    def self.csv(result)
      CSV.generate(headers: true) do |csv|
        csv << %w[store region title score verdict completed_at validated_at visit_id]
        result.entries.each do |entry|
          region_name = place_name(entry.store)
          csv << [
            entry.store.name,
            region_name,
            entry.title,
            entry.score,
            entry.verdict,
            entry.completed_at&.iso8601,
            entry.validated_at&.iso8601,
            entry.visit_id
          ]
        end
      end
    end

    def self.place_name(store)
      current = store.parent
      guard = 0
      while current && guard < 8
        return current.name if current.unit_type == "region"
        current = current.parent
        guard += 1
      end
      store.parent&.name
    end

    def initialize(tenant, store_ids: nil, store: nil, region: nil, limit: 100)
      @tenant = tenant
      @store = store
      @region = region
      @store_ids = Array(store_ids).presence || scoped_store_ids
      @limit = limit
    end

    def call
      entries = build_entries
      store_rows = build_store_rows(entries)
      Result.new(
        entries: entries,
        store_rows: store_rows,
        region_rows: build_region_rows(store_rows),
        store: @store,
        region: @region
      )
    end

    private

    def scoped_store_ids
      if @store
        [ @store.id ]
      elsif @region
        @region.descendant_stores.pluck(:id)
      else
        @tenant.org_units.stores.pluck(:id)
      end
    end

    def build_entries
      return [] if @store_ids.empty?

      scope = Delivery.joins(:communication)
                      .includes(:photo_before_attachment, :photo_after_attachment, proof_files_attachments: :blob, delivery_answers: [ :communication_question, { image_attachment: :blob } ], org_unit: :parent, communication: :visit)
                      .where(communications: { tenant_id: @tenant.id, status: "sent" })
                      .where(org_unit_id: @store_ids)
                      .where.not(score: nil)
                      .order(Arel.sql("COALESCE(deliveries.completed_at, deliveries.validated_at, deliveries.updated_at) DESC"), :id)

      scope.limit(@limit).map do |delivery|
        Entry.new(
          delivery: delivery,
          store: delivery.org_unit,
          title: delivery.communication.title,
          score: delivery.score,
          verdict: delivery.verdict,
          completed_at: delivery.completed_at,
          validated_at: delivery.validated_at,
          visit_id: delivery.communication.visit_id
        )
      end
    end

    def build_store_rows(entries)
      grouped = entries.group_by { |entry| entry.store.id }
      stores = @tenant.org_units.stores.where(id: @store_ids).order(:name)
      stores.filter_map do |store|
        audits = grouped[store.id] || []
        next if audits.empty? && @store.nil?

        scores = audits.map(&:score).compact
        last = audits.first
        verdicts = audits.map(&:verdict)
        StoreRow.new(
          store: store,
          audits: audits.size,
          avg_score: scores.empty? ? nil : (scores.sum.to_f / scores.size).round,
          last_score: last&.score,
          last_verdict: last&.verdict,
          last_at: last&.completed_at || last&.validated_at,
          conforme: verdicts.count("conforme"),
          improve: verdicts.count("improve"),
          non_conforme: verdicts.count("non_conforme")
        )
      end
    end

    def build_region_rows(store_rows)
      units = @tenant.org_units.index_by(&:id)
      grouped = Hash.new { |hash, key| hash[key] = [] }

      store_rows.each do |row|
        region = region_for(row.store, units)
        key = region&.id || :unassigned
        grouped[key] << row
      end

      grouped.map do |key, rows|
        region = key == :unassigned ? nil : units[key]
        score_total = rows.sum { |row| row.avg_score.to_i * row.audits }
        audit_total = rows.sum(&:audits)
        RegionRow.new(
          region: region,
          stores: rows.size,
          audits: audit_total,
          avg_score: audit_total.zero? ? nil : (score_total.to_f / audit_total).round,
          conforme: rows.sum(&:conforme),
          improve: rows.sum(&:improve),
          non_conforme: rows.sum(&:non_conforme)
        )
      end.sort_by { |row| [ -(row.avg_score || -1), row.region&.name.to_s ] }
    end

    def region_for(store, units)
      current = units[store.parent_id]
      guard = 0
      while current && guard < 8
        return current if current.unit_type == "region"

        current = units[current.parent_id]
        guard += 1
      end
      nil
    end
  end
end
