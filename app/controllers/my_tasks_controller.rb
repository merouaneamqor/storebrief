class MyTasksController < ApplicationController
  before_action -> { require_feature!(:briefs) }

  def index
    @filter = params[:filter].presence_in(Vazivo::MyTasks::FILTERS)
    @tasks = Vazivo::MyTasks.for(user: current_user, tenant: tenant_scope, filter: @filter)
  end

  def show
    @task = Vazivo::MyTasks.find(
      user: current_user, tenant: tenant_scope, id: params[:id], kind: params[:kind]
    )
    return if @task

    redirect_to my_tasks_path, alert: t("morocco.my_tasks.missing")
  end
end
