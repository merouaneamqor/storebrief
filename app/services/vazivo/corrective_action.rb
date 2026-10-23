module Vazivo
  # Spawns a store-assigned Communication task from an audit issue
  # (delivery verdict improve/non_conforme, or a failed checklist item).
  class CorrectiveAction
    ISSUE_VERDICTS = %w[improve non_conforme].freeze
    DEFAULT_DEADLINE_DAYS = 3
    DEADLINE_DAYS_RANGE = 1..30

    class Error < StandardError; end

    def self.spawn_from_delivery!(delivery:, author:, visit: nil, due_at: nil, title_fr: nil, body_fr: nil, title_ar: nil, body_ar: nil)
      new(author:).spawn_from_delivery!(
        delivery:,
        visit:,
        due_at:,
        title_fr:,
        body_fr:,
        title_ar:,
        body_ar:
      )
    end

    def self.spawn_from_checklist_item!(response:, author:, visit: nil, due_at: nil, title_fr: nil, body_fr: nil, title_ar: nil, body_ar: nil)
      new(author:).spawn_from_checklist_item!(
        response:,
        visit:,
        due_at:,
        title_fr:,
        body_fr:,
        title_ar:,
        body_ar:
      )
    end

    def self.default_due_at(tenant)
      days = normalize_deadline_days(tenant.corrective_deadline_days)
      local = Schedule.now + days.days
      close_hour, close_min = Schedule.parse_hm(tenant.effective_close, fallback: [ 21, 0 ])
      Schedule.adjust(tenant, local.change(hour: close_hour, min: close_min, sec: 0))
    end

    def self.normalize_deadline_days(value)
      days = value.to_i
      return DEFAULT_DEADLINE_DAYS unless DEADLINE_DAYS_RANGE.cover?(days)

      days
    end

    def self.issue_verdict?(verdict)
      ISSUE_VERDICTS.include?(verdict.to_s)
    end

    def initialize(author:)
      @author = author
    end

    def spawn_from_delivery!(delivery:, visit: nil, due_at: nil, title_fr: nil, body_fr: nil, title_ar: nil, body_ar: nil)
      communication = delivery.communication
      tenant = communication.tenant
      assert_author!(tenant, delivery.org_unit)
      assert_morocco!(tenant)
      raise Error, I18n.t("morocco.corrective.not_an_issue") unless self.class.issue_verdict?(delivery.verdict)
      raise Error, I18n.t("morocco.corrective.already_exists") if existing_for_delivery?(tenant, delivery)

      visit = resolve_visit!(tenant, visit, delivery.org_unit)
      due = due_at.present? ? Schedule.adjust(tenant, due_at) : self.class.default_due_at(tenant)

      title_fr = title_fr.presence || I18n.t(
        "morocco.corrective.title_from_delivery",
        title: communication.title_fr,
        verdict: I18n.t("morocco.verdict.#{delivery.verdict}", locale: :fr),
        locale: :fr
      )
      body_fr = body_fr.presence || default_body_from_delivery(delivery, visit)

      create_and_send!(
        tenant:,
        store: delivery.org_unit,
        visit:,
        due:,
        title_fr:,
        title_ar: title_ar.presence,
        body_fr:,
        body_ar: body_ar.presence,
        source_delivery: delivery,
        source_checklist_item_response: nil
      )
    end

    def spawn_from_checklist_item!(response:, visit: nil, due_at: nil, title_fr: nil, body_fr: nil, title_ar: nil, body_ar: nil)
      item = response.checklist_item
      delivery = response.checklist_delivery
      checklist = delivery.checklist
      tenant = checklist.tenant
      assert_author!(tenant, delivery.org_unit)
      assert_morocco!(tenant)
      raise Error, I18n.t("morocco.corrective.item_ok") unless item_needs_corrective?(item, response)
      raise Error, I18n.t("morocco.corrective.already_exists") if existing_for_checklist_item?(tenant, response)

      visit = resolve_visit!(tenant, visit, delivery.org_unit)
      due = due_at.present? ? Schedule.adjust(tenant, due_at) : self.class.default_due_at(tenant)

      title_fr = title_fr.presence || I18n.t(
        "morocco.corrective.title_from_item",
        title: item.title_fr,
        locale: :fr
      )
      body_fr = body_fr.presence || default_body_from_item(item, response, checklist, visit)

      create_and_send!(
        tenant:,
        store: delivery.org_unit,
        visit:,
        due:,
        title_fr:,
        title_ar: title_ar.presence || item.title_ar,
        body_fr:,
        body_ar: body_ar.presence,
        source_delivery: nil,
        source_checklist_item_response: response
      )
    end

    private

    def assert_author!(tenant, unit)
      raise Error, I18n.t("auth.hq_required") unless @author.tenant_id == tenant.id
      allowed = @author.super_admin? || @author.permitted_store_ids(:verdicts, :escalate).include?(unit.id)
      raise Error, I18n.t("auth.hq_required") unless allowed
    end

    def assert_morocco!(tenant)
      raise Error, I18n.t("auth.feature_disabled") unless tenant.feature?(:morocco_ops)
    end

    def existing_for_delivery?(tenant, delivery)
      tenant.communications.exists?(source: "corrective", source_delivery_id: delivery.id)
    end

    def existing_for_checklist_item?(tenant, response)
      tenant.communications.exists?(source: "corrective", source_checklist_item_response_id: response.id)
    end

    def item_needs_corrective?(item, response)
      return true if item.required? && !response.completed?
      return true if item.requires_photo? && !response.evidence_attached?

      false
    end

    def resolve_visit!(tenant, visit, store)
      return if visit.blank?
      raise Error, I18n.t("morocco.corrective.visit_mismatch") unless visit.tenant_id == tenant.id
      raise Error, I18n.t("morocco.corrective.visit_mismatch") unless visit.org_unit_id == store.id

      visit
    end

    def default_body_from_delivery(delivery, visit)
      parts = []
      parts << I18n.t(
        "morocco.corrective.body_verdict",
        verdict: I18n.t("morocco.verdict.#{delivery.verdict}", locale: :fr),
        store: delivery.org_unit.name,
        locale: :fr
      )
      parts << delivery.verdict_note if delivery.verdict_note.present?
      if delivery.score.present?
        parts << I18n.t("morocco.verdict.score", score: delivery.score, locale: :fr)
      end
      if visit
        parts << I18n.t(
          "morocco.corrective.body_visit",
          store: visit.org_unit.name,
          when: I18n.l(visit.planned_at, format: :long, locale: :fr),
          locale: :fr
        )
      end
      parts.join("\n\n")
    end

    def default_body_from_item(item, response, checklist, visit)
      parts = []
      parts << I18n.t(
        "morocco.corrective.body_item",
        item: item.title_fr,
        checklist: checklist.title_fr,
        store: response.checklist_delivery.org_unit.name,
        locale: :fr
      )
      parts << response.notes if response.notes.present?
      if item.requires_photo? && !response.evidence_attached?
        parts << I18n.t("morocco.corrective.body_missing_evidence", locale: :fr)
      end
      if visit
        parts << I18n.t(
          "morocco.corrective.body_visit",
          store: visit.org_unit.name,
          when: I18n.l(visit.planned_at, format: :long, locale: :fr),
          locale: :fr
        )
      end
      parts.join("\n\n")
    end

    def create_and_send!(tenant:, store:, visit:, due:, title_fr:, title_ar:, body_fr:, body_ar:, source_delivery:, source_checklist_item_response:)
      tenant.transaction do
        brief = tenant.communications.create!(
          author: @author,
          format: "task",
          status: "draft",
          source: "corrective",
          priority: "important",
          requires_proof: true,
          title_fr: title_fr,
          title_ar: title_ar,
          body_fr: body_fr,
          body_ar: body_ar,
          due_at: due,
          visit: visit,
          source_delivery: source_delivery,
          source_checklist_item_response: source_checklist_item_response
        )
        brief.send_to!([ store.id ])
        brief
      end
    end
  end
end
