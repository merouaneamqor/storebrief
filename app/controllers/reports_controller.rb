class ReportsController < ApplicationController
  before_action :require_hq

  def show
    @report = Reports::Snapshot.new(tenant_scope)
  end
end
