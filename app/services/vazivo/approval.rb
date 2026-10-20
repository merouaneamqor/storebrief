module Vazivo
  # HQ approval gate before a brief is sent or a playbook is deployed.
  # Tenant opt-in via the `send_approval` feature flag (default off).
  module Approval
    class Error < ArgumentError; end
    class Required < Error; end
    class NotAllowed < Error; end
    class SelfApproval < NotAllowed; end
    class NotPending < Error; end
    class NoteRequired < Error; end

    DECISIONS = %w[approved rejected].freeze

    module_function

    def required?(tenant)
      tenant.feature?(:send_approval)
    end

    def can_approve?(user)
      return false unless user

      user.hq? && Membership.allows?("hq", :approve)
    end

    # Does this communication need an approved review before send_to!?
    # Occurrences clone an already approved series source; corrective and playbook
    # briefs are system generated (playbooks are gated at deploy time).
    def gate?(communication)
      required?(communication.tenant) && communication.source == "compose" && !communication.occurrence?
    end

    def ensure_sendable!(communication)
      return unless gate?(communication)
      return if communication.review_approved?

      raise Required, I18n.t("approval.errors.required")
    end

    def ensure_deployable!(tenant, request, playbook)
      return unless required?(tenant)
      return if request&.review_approved? && !request.deployed? &&
                request.tenant_id == tenant.id && request.playbook_id == playbook.id

      raise Required, I18n.t("approval.errors.required")
    end

    def submit!(subject, actor:)
      subject.transaction do
        subject.update!(review_status: "pending_review", reviewed_by: nil, reviewed_at: nil, review_note: nil)
        record!(subject, "submitted", actor)
      end
      subject
    end

    # Approve or reject. The optional block runs inside the transaction after the
    # status change (used to deploy a playbook atomically with its approval).
    def decide!(subject, approver:, decision:, note: nil)
      decision = decision.to_s
      raise Error, I18n.t("approval.errors.invalid_decision") unless DECISIONS.include?(decision)

      subject.transaction do
        subject.lock!
        authorize!(subject, approver)
        raise NotPending, I18n.t("approval.errors.not_pending") unless subject.review_pending?
        raise NoteRequired, I18n.t("approval.errors.note_required") if decision == "rejected" && note.to_s.strip.blank?

        subject.update!(review_status: decision, reviewed_by: approver, reviewed_at: Time.current,
                        review_note: note.to_s.strip.presence)
        record!(subject, decision == "approved" ? "approved" : "rejected", approver, note)
        yield subject if block_given?
      end
      notify_author!(subject, decision)
      subject
    end

    def authorize!(subject, approver)
      unless can_approve?(approver) && approver.tenant_id == subject.tenant_id
        raise NotAllowed, I18n.t("approval.errors.not_allowed")
      end
      return unless required?(subject.tenant) && subject.author_id == approver.id

      raise SelfApproval, I18n.t("approval.errors.self_approval")
    end

    def record!(subject, kind, actor, note = nil)
      ApprovalEvent.create!(tenant_id: subject.tenant_id, subject: subject, actor: actor, kind: kind,
                            note: note.to_s.strip.presence)
    end

    # Push is free; skipped quietly when push is off or the author has no device.
    def notify_author!(subject, decision)
      tenant = subject.tenant
      return unless tenant.feature?(:push_alerts) && WebPushConfig.configured?

      author = subject.author
      PushNotifier.deliver_to_user!(
        user: author,
        tenant: tenant,
        notifiable: subject,
        title: I18n.t("approval.push.#{decision}", locale: author.locale),
        body: subject_title(subject, author.locale),
        url: subject_url(subject)
      )
    end

    def subject_title(subject, locale)
      record = subject.is_a?(PlaybookDeployRequest) ? subject.playbook : subject
      record.localized_value(:title, locale: locale).to_s
    end

    def subject_url(subject)
      helpers = Rails.application.routes.url_helpers
      if subject.is_a?(PlaybookDeployRequest)
        helpers.playbook_deploy_requests_path
      else
        helpers.edit_communication_path(subject)
      end
    end
  end
end
