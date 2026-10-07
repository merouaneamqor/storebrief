# Run at least daily (hourly is fine, it is idempotent) to send the next
# occurrence of every recurring task brief that is due.
class RecurringTaskJob < ApplicationJob
  queue_as :default

  def perform
    Vazivo::Recurrence.spawn_all!
  end
end
