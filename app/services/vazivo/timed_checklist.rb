module Vazivo
  # Today's checklist work for a store, ordered by due time.
  # Buckets map template categories (and playbooks) to opening / merch / stock / campaign.
  class TimedChecklist
    BUCKETS = %w[opening merch stock campaign].freeze

    CATEGORY_BUCKET = {
      "opening" => "opening",
      "closing" => "opening",
      "safety" => "opening",
      "promotions" => "merch",
      "equipment" => "stock",
      "cleanliness" => "stock",
      "store_visit" => "stock"
    }.freeze

    Line = Struct.new(
      :item_id, :title, :completed, :requires_photo, :position,
      keyword_init: true
    )
    Entry = Struct.new(
      :delivery_id, :title, :due_at, :bucket, :tone, :completed, :path,
      :done_count, :total_count, :lines, :offline,
      keyword_init: true
    )

    def self.for(store:, tenant:, user: nil, offline: false)
      new(store:, tenant:, user:, offline:).entries
    end

    def initialize(store:, tenant:, user: nil, offline: false)
      @store = store
      @tenant = tenant
      @user = user
      @offline = offline
    end

    def entries
      deliveries.map { |delivery| to_entry(delivery) }
    end

    private

    def deliveries
      day = Schedule.now.all_day
      scope = ChecklistDelivery.joins(:checklist)
                               .where(org_unit_id: @store.id, checklists: { tenant_id: @tenant.id, status: "sent" })
                               .includes(:checklist, checklist: [ :checklist_template, :checklist_items, :playbook ],
                                         checklist_item_responses: [])

      open = scope.where.not(status: "completed").to_a
      done_today = scope.where(status: "completed", completed_at: day).to_a

      (open + done_today).uniq(&:id).select { |delivery| include?(delivery) }.sort_by { |delivery| sort_key(delivery) }
    end

    def include?(delivery)
      return true if delivery.due_today? || delivery.late?
      return true if delivery.completed? && delivery.completed_at.present? &&
                     delivery.completed_at.in_time_zone(Schedule::ZONE).to_date == Schedule.now.to_date

      delivery.due_at.blank? && delivery.pending?
    end

    def sort_key(delivery)
      [ delivery.due_at || Schedule.now.end_of_day, delivery.id ]
    end

    def to_entry(delivery)
      checklist = delivery.checklist
      responses = delivery.checklist_item_responses.index_by(&:checklist_item_id)
      lines = checklist.checklist_items.map do |item|
        response = responses[item.id]
        Line.new(
          item_id: item.id,
          title: item.title,
          completed: response&.completed? || delivery.completed?,
          requires_photo: item.requires_photo?,
          position: item.position
        )
      end
      done = lines.count(&:completed)
      total = lines.size
      routes = Rails.application.routes.url_helpers
      owned = @user.nil? || @user.store_org_unit&.id == @store.id

      Entry.new(
        delivery_id: delivery.id,
        title: checklist.title,
        due_at: delivery.due_at,
        bucket: bucket_for(checklist),
        tone: delivery.tone,
        completed: delivery.completed?,
        path: (routes.checklists_delivery_path(delivery) if owned),
        done_count: done,
        total_count: total,
        lines: lines,
        offline: @offline
      )
    end

    def bucket_for(checklist)
      return "campaign" if checklist.playbook_id.present?

      category = checklist.checklist_template&.category
      CATEGORY_BUCKET.fetch(category.to_s, "opening")
    end
  end
end
