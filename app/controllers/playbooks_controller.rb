class PlaybooksController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:checklists) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action :set_playbook, only: %i[edit update destroy reset deploy]

  def index
    @playbooks = Playbook.ensure_defaults!(tenant_scope)
    @stores = tenant_scope.org_units.stores.order(:name)
    @selected_key = params[:key].presence || @playbooks.first&.key
  end

  def new
    @playbook = tenant_scope.playbooks.new(
      title_fr: "",
      description_fr: "",
      steps: [ { "offset_days" => -7, "title_fr" => "", "title_ar" => "", "requires_photo" => false } ]
    )
  end

  def create
    @playbook = tenant_scope.playbooks.new(playbook_attrs)
    @playbook.key = Playbook.assign_unique_key!(tenant_scope, @playbook.title_fr)

    if @playbook.save
      redirect_to playbooks_path(key: @playbook.key), notice: t("morocco.playbooks.saved", title: @playbook.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @playbook.update(playbook_attrs)
      redirect_to playbooks_path(key: @playbook.key), notice: t("morocco.playbooks.saved", title: @playbook.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless @playbook.custom?
      redirect_to playbooks_path(key: @playbook.key), alert: t("morocco.playbooks.cannot_delete_system")
      return
    end

    key = @playbook.key
    @playbook.destroy!
    redirect_to playbooks_path, notice: t("morocco.playbooks.deleted", title: key)
  end

  def reset
    @playbook.reset_to_default!
    redirect_to playbooks_path(key: @playbook.key), notice: t("morocco.playbooks.reset", title: @playbook.title)
  rescue ArgumentError => e
    redirect_to playbooks_path(key: @playbook.key), alert: e.message
  end

  def deploy
    campaign_on = parse_date(params[:campaign_on])
    if campaign_on.nil?
      redirect_to playbooks_path(key: @playbook.key), alert: t("morocco.playbooks.date_required")
      return
    end

    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: current_user,
      campaign_on: campaign_on,
      org_unit_ids: params[:org_unit_ids]
    )
    redirect_to playbooks_path(key: @playbook.key), notice: t("morocco.playbooks.deployed", title: @playbook.title)
  rescue ArgumentError => e
    redirect_to playbooks_path(key: @playbook.key), alert: e.message
  end

  private

  def set_playbook
    @playbook = tenant_scope.playbooks.find(params[:id])
  end

  def playbook_attrs
    permitted = params.require(:playbook).permit(
      :title_fr, :title_ar, :description_fr, :description_ar,
      steps: [ :offset_days, :title_fr, :title_ar, :requires_photo ]
    )
    permitted[:steps] = Playbook.normalize_steps(permitted[:steps])
    permitted
  end

  def parse_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
