class NewsfeedsController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action :set_store

  def index
    result = Vazivo::Newsfeed.for(
      store: @store,
      tenant: tenant_scope,
      page: params[:page],
      per_page: params[:per_page]
    )
    @deliveries = result.deliveries
    @page = result.page
    @per_page = result.per_page
    @total_count = result.total_count
    @total_pages = result.total_pages
  end

  private

  def set_store
    unless store_user?
      redirect_to app_root_path, alert: t("auth.hq_required")
      return
    end

    @store = current_user.store_org_unit
    return if @store

    redirect_to app_root_path, alert: t("errors.no_store")
  end
end
