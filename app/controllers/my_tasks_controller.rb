class MyTasksController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_store_or_area_user

  def index
    @snapshot = Vazivo::MyTasks.for(user: current_user, tenant: tenant_scope, filter: params[:filter])
  end

  private

  def require_store_or_area_user
    return if current_user.store? || current_user.area?

    redirect_to app_root_path
  end
end
