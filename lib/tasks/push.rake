# frozen_string_literal: true

namespace :push do
  desc "Remind store users about briefs/checklists still pending (Web Push)"
  task remind_pending: :environment do
    unless WebPushConfig.configured?
      puts "VAPID not configured — skipping push reminders."
      next
    end

    sent = PushReminder.notify_pending!
    puts "Push reminders sent: #{sent}"
  end
end
