module Vazivo
  class PlaybookDeployer
    def self.deploy!(playbook:, author:, campaign_on:, org_unit_ids:, starts_on: nil, brief_fr: nil, brief_ar: nil,
                    request: nil)
      tenant = playbook.tenant
      Approval.ensure_deployable!(tenant, request, playbook)
      targets = CampaignTargets.new(tenant, org_unit_ids)
      raise ArgumentError, I18n.t("errors.select_targets") if targets.empty?

      starts_on = starts_on.presence || earliest_step_day(playbook, campaign_on)
      raise ArgumentError, I18n.t("morocco.playbooks.invalid_range") if starts_on > campaign_on

      body_fr = brief_fr.presence || playbook.description_fr
      body_ar = brief_ar.presence || playbook.description_ar
      raise ArgumentError, I18n.t("morocco.playbooks.brief_required") if body_fr.blank?

      due = Schedule.default_due(tenant, campaign_on.in_time_zone(Schedule::ZONE).change(hour: 18))

      tenant.transaction do
        checklist = tenant.checklists.create!(
          author: author,
          playbook: playbook,
          starts_on: starts_on,
          campaign_on: campaign_on,
          title_fr: playbook.title_fr,
          title_ar: playbook.title_ar,
          description_fr: body_fr,
          description_ar: body_ar,
          status: "draft",
          target_snapshot: targets.snapshot
        )

        position = 0
        playbook.step_list.each do |step|
          day = step_day(campaign_on, step)
          # Clamp into the campaign window so starter offsets stay visible on short ranges.
          day = day.clamp(starts_on, campaign_on)
          checklist.checklist_items.create!(
            position: position,
            title_fr: step_title(step, day: day, campaign_on: campaign_on),
            title_ar: step["title_ar"],
            requires_photo: ActiveModel::Type::Boolean.new.cast(step["requires_photo"])
          )
          position += 1
        end
        checklist.send_to!(targets.store_ids)

        brief = tenant.communications.create!(
          author: author,
          playbook: playbook,
          format: "task",
          status: "draft",
          source: "playbook",
          title_fr: playbook.title_fr,
          title_ar: playbook.title_ar,
          body_fr: body_fr,
          body_ar: body_ar,
          due_at: due,
          requires_proof: false
        )
        brief.send_to!(targets.store_ids)
        brief
      end
    end

    def self.earliest_step_day(playbook, campaign_on)
      offsets = playbook.step_list.map { |step| step["offset_days"].to_i }
      return campaign_on if offsets.empty?

      campaign_on + offsets.min
    end

    def self.step_day(campaign_on, step)
      campaign_on + step["offset_days"].to_i
    end

    def self.step_title(step, day:, campaign_on:)
      offset = (day - campaign_on).to_i
      prefix = offset.zero? ? "J" : "J#{offset}"
      "#{prefix} · #{step['title_fr']}"
    end
  end
end
