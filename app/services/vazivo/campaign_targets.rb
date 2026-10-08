module Vazivo
  # Explicit campaign target set. Selection is made of org units (region, area
  # or store) and resolves to the stores underneath them, always inside the
  # tenant. Store format/cluster attributes do not exist yet; when they do, add
  # them as extra selectors here and in the snapshot.
  class CampaignTargets
    Option = Struct.new(:unit, :depth, keyword_init: true)

    def self.options(tenant)
      units = tenant.org_units.order(:name).to_a
      by_parent = units.group_by(&:parent_id)
      walk = lambda do |parent_id, depth|
        Array(by_parent[parent_id]).flat_map do |unit|
          [ Option.new(unit: unit, depth: depth) ] + walk.call(unit.id, depth + 1)
        end
      end
      walk.call(nil, 0)
    end

    attr_reader :tenant

    def initialize(tenant, org_unit_ids)
      @tenant = tenant
      @org_unit_ids = Array(org_unit_ids).compact_blank.map(&:to_i).uniq
    end

    def selected_units
      @selected_units ||= tenant.org_units.where(id: @org_unit_ids).order(:id).to_a
    end

    def stores
      @stores ||= begin
        ids = selected_units.flat_map { |unit| unit.descendant_stores.pluck(:id) }.uniq
        tenant.org_units.stores.where(id: ids).order(:name).to_a
      end
    end

    def store_ids
      stores.map(&:id)
    end

    def empty?
      stores.empty?
    end

    def preview
      {
        count: stores.size,
        stores: stores.map { |store| store_entry(store) }
      }
    end

    def snapshot
      {
        "captured_at" => Time.current.iso8601,
        "selection" => selected_units.map { |unit| { "id" => unit.id, "name" => unit.name, "unit_type" => unit.unit_type } },
        "store_count" => stores.size,
        "stores" => stores.map { |store| store_entry(store).stringify_keys }
      }
    end

    private

    def store_entry(store)
      { id: store.id, name: store.name, region: ancestor_name(store, "region"), area: ancestor_name(store, "area") }
    end

    def ancestor_name(unit, type)
      node = unit.parent
      node = node.parent while node && node.unit_type != type
      node&.name
    end
  end
end
