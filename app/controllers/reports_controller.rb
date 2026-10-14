class ReportsController < ApplicationController
  before_action -> { require_hq_or_area(:reports) }
  before_action -> { require_feature!(:reports) }

  def show
    @report = Reports::Snapshot.new(tenant_scope)
  end
end
