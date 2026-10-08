class EscalationJob < ApplicationJob
  queue_as :default

  def perform
    Vazivo::Escalation.sweep_all!
  end
end
