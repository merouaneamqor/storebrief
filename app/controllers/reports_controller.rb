class ReportsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:reports) }

  def show
    @report = Reports::Snapshot.new(tenant_scope)
  end
end
