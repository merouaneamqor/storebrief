module Vazivo
  class PlaybookDeployer
    def self.deploy!(playbook:, author:, campaign_on:, org_unit_ids:)
      tenant = playbook.tenant
      targets = CampaignTargets.new(tenant, org_unit_ids)
      raise ArgumentError, I18n.t("errors.select_targets") if targets.empty?

      due = Schedule.default_due(tenant, campaign_on.in_time_zone(Schedule::ZONE).change(hour: 18))

      tenant.transaction do
        checklist = tenant.checklists.create!(
          author: author,
          playbook: playbook,
          campaign_on: campaign_on,
          title_fr: playbook.title_fr,
          title_ar: playbook.title_ar,
          description_fr: playbook.description_fr,
          description_ar: playbook.description_ar,
          status: "draft",
          target_snapshot: targets.snapshot
        )
        playbook.step_list.each_with_index do |step, index|
          checklist.checklist_items.create!(
            position: index,
            title_fr: step_title(step),
            title_ar: step["title_ar"],
            requires_photo: ActiveModel::Type::Boolean.new.cast(step["requires_photo"])
          )
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
          body_fr: playbook.description_fr,
          body_ar: playbook.description_ar,
          due_at: due,
          requires_proof: false
        )
        brief.send_to!(targets.store_ids)
        brief
      end
    end

    def self.step_title(step)
      offset = step["offset_days"].to_i
      prefix = offset.zero? ? "J" : "J#{offset}"
      "#{prefix} · #{step['title_fr']}"
    end
  end
end
