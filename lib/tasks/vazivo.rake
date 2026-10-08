namespace :vazivo do
  desc "Stamp owners and deadlines on open deliveries that still lack them"
  task backfill_assignments: :environment do
    Vazivo::Assignment.backfill_all!
    puts "Backfilled open deliveries."
  end

  desc "Chase overdue store work up the line"
  task escalate: :environment do
    EscalationJob.perform_now
    puts "Escalation sweep done."
  end

  desc "Create due occurrences of recurring task briefs"
  task recurring: :environment do
    RecurringTaskJob.perform_now
    puts "Recurring tasks done."
  end
end
