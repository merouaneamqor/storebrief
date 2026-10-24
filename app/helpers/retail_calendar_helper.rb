module RetailCalendarHelper
  def retail_calendar_event_path(event)
    case event.kind
    when "visit"
      visit_path(event.record) unless store_user?
    when "task"
      if store_user?
        inbox_path(event.record)
      else
        communication_path(event.record.communication, anchor: "store-#{event.record.org_unit_id}")
      end
    when "campaign"
      if store_user?
        checklists_delivery_path(event.record)
      elsif hq_user?
        checklist_path(event.record.checklist, anchor: "store-#{event.record.org_unit_id}")
      else
        store_path(event.record.org_unit)
      end
    end
  end
end
