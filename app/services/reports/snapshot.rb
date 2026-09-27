class Reports::Snapshot
  STALE_AFTER = 3.days
  AGING_AFTER = 1.day
  CHART_LIMIT = 8

  def initialize(tenant)
    @tenant = tenant
  end

  def store_rows
    @store_rows ||= build_store_rows
  end

  def summary
    @summary ||= {
      stores: stores.size,
      behind: store_rows.count { |row| row[:pending].positive? },
      clear: store_rows.count { |row| row[:pending].zero? },
      brief_percent: percent(brief_done, brief_total),
      checklist_percent: percent(check_done, check_total),
      open_briefs: open_brief_count,
      open_checklists: open_check_count
    }
  end

  def ages
    @ages ||= begin
      counts = { fresh: 0, recent: 0, stale: 0 }
      (brief_pairs + check_pairs).each do |_org_unit_id, created_at|
        age = Time.current - created_at
        key = if age >= STALE_AFTER
          :stale
        elsif age >= AGING_AFTER
          :recent
        else
          :fresh
        end
        counts[key] += 1
      end
      counts
    end
  end

  def age_buckets
    total = ages.values.sum
    [
      { key: "age_fresh", count: ages[:fresh], tone: "ok" },
      { key: "age_recent", count: ages[:recent], tone: "watch" },
      { key: "age_stale", count: ages[:stale], tone: "urgent" }
    ].map do |bucket|
      bucket.merge(percent: total.zero? ? 0 : ((bucket[:count].to_f / total) * 100).round)
    end
  end

  def insight
    return { tone: "empty", key: "insight_empty" } if stores.empty?
    return { tone: "ok", key: "insight_clear" } if summary[:behind].zero?

    focus = store_rows.find { |row| row[:priority] }
    if ages[:stale].positive?
      { tone: "urgent", key: "insight_stale", count: ages[:stale], store: focus[:store].name }
    else
      {
        tone: "watch",
        key: "insight_watch",
        behind: summary[:behind],
        store: focus[:store].name,
        count: focus[:pending],
        when: focus[:oldest_at]
      }
    end
  end

  def regions
    @regions ||= build_regions
  end

  def chart_workload
    rows = store_rows.select { |row| row[:pending].positive? }.first(CHART_LIMIT)
    {
      names: rows.map { |row| row[:store].name },
      briefs: rows.map { |row| row[:briefs] },
      checks: rows.map { |row| row[:checks] }
    }
  end

  def open_briefs
    @open_briefs ||= pending_briefs.includes(:org_unit, :communication).order("deliveries.created_at").limit(15)
  end

  def open_checklists
    @open_checklists ||= pending_checks.includes(:org_unit, :checklist).order("checklist_deliveries.created_at").limit(15)
  end

  def open_items?
    (open_brief_count + open_check_count).positive?
  end

  private

  def build_regions
    grouped = store_rows.group_by { |row| row[:place]&.name }
    return [] if grouped.keys.compact.uniq.size < 2

    grouped.map do |name, rows|
      {
        name: name.presence || I18n.t("reports.unassigned"),
        behind: rows.count { |row| row[:pending].positive? },
        pending: rows.sum { |row| row[:pending] },
        stores: rows.size
      }
    end.sort_by { |row| [ -row[:behind], -row[:pending], row[:name] ] }
  end

  def build_store_rows
    rows = stores.map do |store|
      briefs = brief_counts[store.id].to_i
      checks = check_counts[store.id].to_i
      oldest = [ brief_oldest[store.id], check_oldest[store.id] ].compact.min
      pending = briefs + checks
      age_in_days = oldest ? (Time.current - oldest) / 1.day : 0

      {
        store: store,
        place: place_for(store),
        briefs: briefs,
        checks: checks,
        pending: pending,
        oldest_at: oldest,
        stale: oldest.present? && oldest <= STALE_AFTER.ago,
        # Older open work outranks a larger pile of items that just arrived.
        score: pending + (age_in_days * 2)
      }
    end.sort_by { |row| [ -row[:score], row[:store].name ] }

    priority = rows.find { |row| row[:pending].positive? }
    priority[:priority] = true if priority
    rows.each { |row| row[:priority] ||= false }
    rows
  end

  def stores
    @stores ||= units.values.select(&:store?).sort_by(&:name)
  end

  def units
    @units ||= @tenant.org_units.index_by(&:id)
  end

  def place_for(store)
    region = nil
    area = nil
    current = units[store.parent_id]
    guard = 0
    while current && guard < 8
      region ||= current if current.unit_type == "region"
      area ||= current if current.unit_type == "area"
      current = units[current.parent_id]
      guard += 1
    end
    region || area
  end

  def brief_pairs
    @brief_pairs ||= pending_briefs.pluck("deliveries.org_unit_id", "deliveries.created_at")
  end

  def check_pairs
    @check_pairs ||= pending_checks.pluck("checklist_deliveries.org_unit_id", "checklist_deliveries.created_at")
  end

  def brief_counts
    @brief_counts ||= brief_pairs.each_with_object(Hash.new(0)) { |(id, _), counts| counts[id] += 1 }
  end

  def check_counts
    @check_counts ||= check_pairs.each_with_object(Hash.new(0)) { |(id, _), counts| counts[id] += 1 }
  end

  def brief_oldest
    @brief_oldest ||= oldest_by_store(brief_pairs)
  end

  def check_oldest
    @check_oldest ||= oldest_by_store(check_pairs)
  end

  def oldest_by_store(pairs)
    pairs.each_with_object({}) do |(id, created_at), oldest|
      current = oldest[id]
      oldest[id] = created_at if current.nil? || created_at < current
    end
  end

  def pending_briefs
    Delivery.joins(:communication).where(communications: { tenant_id: @tenant.id, status: "sent" }, deliveries: { status: "pending" })
  end

  def pending_checks
    ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: @tenant.id, status: "sent" }, checklist_deliveries: { status: "pending" })
  end

  def sent_briefs
    @sent_briefs ||= Delivery.joins(:communication).where(communications: { tenant_id: @tenant.id, status: "sent" })
  end

  def sent_checks
    @sent_checks ||= ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: @tenant.id, status: "sent" })
  end

  def brief_total
    @brief_total ||= sent_briefs.count
  end

  def brief_done
    @brief_done ||= sent_briefs.where(deliveries: { status: %w[completed read] }).count
  end

  def check_total
    @check_total ||= sent_checks.count
  end

  def check_done
    @check_done ||= sent_checks.where(checklist_deliveries: { status: "completed" }).count
  end

  def open_brief_count
    brief_total - brief_done
  end

  def open_check_count
    check_total - check_done
  end

  def percent(done, total)
    return 0 if total.zero?

    ((done.to_f / total) * 100).round
  end
end
