class OrgUnitsController < ApplicationController
  before_action :require_hq

  def index
    @roots = tenant_scope.org_units.roots.includes(children: :children).order(:name)
  end
end
