module MoroccoHelper
  def morocco_due_label(time)
    return if time.blank?

    local = time.in_time_zone(Vazivo::Schedule::ZONE)
    today = Vazivo::Schedule.now.to_date
    if local.to_date == today
      local.strftime("%H:%M")
    else
      local.strftime("%d/%m %H:%M")
    end
  end
end
