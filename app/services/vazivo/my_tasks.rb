module Vazivo
  # Per-user list of open brief deliveries the user has to carry: either
  # assigned directly to them, or living in a store they manage (store manager
  # on their store, area manager on every store under them).
  class MyTasks
    SCOPES = %w[all overdue today upcoming].freeze
    DEFAULT_SCOPE = "all".freeze

    Result = Struct.new(:scope, :counts, :deliveries, keyword_init: true)

    def self.for(user:, tenant:, scope: DEFAULT_SCOPE)
      new(user, tenant).call(scope: scope)
    end

    def initialize(user, tenant)
      @user = user
      @tenant = tenant
    end

    def call(scope: DEFAULT_SCOPE)
      scope = normalize(scope)
      all = base_relation.to_a
      Result.new(
        scope: scope,
        counts: counts_for(all),
        deliveries: filter(all, scope).sort_by { |delivery| sort_key(delivery) }
      )
    end

    def self.scopes
      SCOPES
    end

    private

    def normalize(scope)
      scope = scope.to_s
      SCOPES.include?(scope) ? scope : DEFAULT_SCOPE
    end

    # current_instances keeps one row per recurring series (the newest sent
    # occurrence), matching the store inbox. Open work only.
    def base_relation
      Delivery.current_instances
              .where(communications: { tenant_id: @tenant.id, status: "sent" })
              .where(status: "pending")
              .where(ownership_sql, store_ids: store_ids_for_query, user_id: @user.id)
              .includes(:communication, :org_unit, :assignee)
    end

    def ownership_sql
      "deliveries.org_unit_id IN (:store_ids) OR deliveries.assignee_id = :user_id"
    end

    def store_ids_for_query
      ids = @user.manageable_store_ids
      ids.empty? ? [ 0 ] : ids
    end

    def filter(deliveries, scope)
      case scope
      when "overdue"  then deliveries.select { |d| overdue?(d) }
      when "today"    then deliveries.select { |d| due_today_future?(d) }
      when "upcoming" then deliveries.select { |d| upcoming?(d) }
      else deliveries
      end
    end

    def counts_for(deliveries)
      {
        all: deliveries.size,
        overdue: deliveries.count { |d| overdue?(d) },
        today: deliveries.count { |d| due_today_future?(d) },
        upcoming: deliveries.count { |d| upcoming?(d) }
      }
    end

    def overdue?(delivery)
      delivery.late?
    end

    def due_today_future?(delivery)
      return false if delivery.due_at.blank?
      return false if overdue?(delivery)

      delivery.due_today?
    end

    def upcoming?(delivery)
      return false if delivery.due_at.blank?
      return false if overdue?(delivery) || due_today_future?(delivery)

      true
    end

    # Due bucket first so overdue work stays at the top of All, then priority
    # (urgent before routine) the way the store inbox orders a tie, then due time.
    def sort_key(delivery)
      rank = if overdue?(delivery) then 0
      elsif due_today_future?(delivery) then 1
      elsif delivery.due_at.present? then 2
      else 3
      end
      created = delivery.communication.created_at || Time.zone.at(0)
      [
        rank,
        delivery.communication.priority_rank,
        delivery.due_at || 100.years.from_now,
        -created.to_f
      ]
    end
  end
end
