class ApplicationController < ActionController::Base
  RESERVED_SUBDOMAINS = %w[www admin mail api].freeze

  helper_method :current_user, :current_tenant, :acting_tenant, :hq_user?, :area_user?,
                :store_user?, :super_admin?, :rtl?, :apex_request?, :host_tenant?,
                :tenant_feature?, :user_allows?

  before_action :redirect_www
  before_action :set_tenant_from_host
  before_action :require_login, unless: :active_admin_controller?
  before_action :bind_session_tenant
  before_action :set_locale
  before_action :require_privacy_acceptance, if: :privacy_gate_required?
  before_action :require_workflow_capability

  private

  def privacy_gate_required?
    current_user.present? && !active_admin_controller? && !privacy_exempt_controller?
  end

  def privacy_exempt_controller?
    is_a?(LegalController) ||
      is_a?(PrivacyPreferencesController) ||
      is_a?(SessionsController)
  end

  def require_privacy_acceptance
    return if current_user.privacy_notice_accepted?

    redirect_to privacy_preferences_path, alert: t("privacy.acceptance.required")
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_tenant
    Current.tenant
  end

  def acting_tenant
    Current.tenant
  end

  def hq_user?
    super_admin? || current_user&.hq?
  end

  def area_user?
    current_user&.area? && !hq_user?
  end

  # Store chrome only: never treat HQ/area as store even if memberships are messy.
  def store_user?
    current_user&.store? && !hq_user? && !area_user?
  end

  def super_admin?
    current_user&.super_admin?
  end

  # Pass the target unit for object-level checks; unscoped checks drive navigation.
  def user_allows?(capability, org_unit: nil, tenant_wide: false)
    return false if org_unit && org_unit.tenant_id != current_tenant&.id
    return true if super_admin?
    return false unless current_user && current_user.tenant_id == current_tenant&.id

    current_user.allows?(capability, org_unit: org_unit, tenant_wide: tenant_wide)
  end

  # Legacy role helpers select chrome and data scopes, never grant a removed
  # custom capability. Keep these entry points consistent with the HQ gates.
  def require_workflow_capability
    return unless current_user && current_user.memberships.where.not(tenant_role_id: nil).exists?

    capability = case controller_name
    when "inbox", "newsfeeds", "feed_engagements", "broadcast_acknowledgements", "delivery_comments" then store_user? ? :inbox : :monitor
    when "checklist_deliveries", "sync" then :execute
    when "my_tasks", "incident_tickets" then store_user? ? :execute : :monitor
    when "rankings" then store_user? ? :inbox : :reports
    when "vm_missions" then store_user? ? :execute : (action_name.in?(%w[index show review]) ? :verdicts : :compose)
    when "dashboard", "stores", "hq_widgets" then store_user? ? :inbox : :monitor
    when "visits" then store_user? ? :inbox : :visits
    when "kb_articles" then action_name.in?(%w[index show]) ? (store_user? ? :inbox : :monitor) : :compose
    end
    return unless capability
    unit = current_user.store_org_unit if store_user?
    return if user_allows?(capability, org_unit: unit, tenant_wide: hq_user?)

    if controller_name == "dashboard"
      destination = if user_allows?(:visits)
        calendar_visits_path
      elsif user_allows?(:reports)
        reports_path
      elsif user_allows?(:compose, tenant_wide: true)
        new_communication_path
      elsif store_user? && user_allows?(:execute, org_unit: unit)
        checklists_deliveries_path
      end
      destination ? redirect_to(destination) : head(:forbidden)
    else
      redirect_to app_root_path, alert: t("auth.hq_required")
    end
  end

  def rtl?
    I18n.locale.to_s == "ar"
  end

  def app_host
    ENV.fetch("APP_HOST", "localhost")
  end

  def app_tld_length
    default = app_host == "localhost" ? "0" : "1"
    ENV.fetch("APP_TLD_LENGTH", default).to_i
  end

  def request_label
    request.subdomains(app_tld_length).first
  end

  def apex_request?
    !host_tenant?
  end

  def host_tenant?
    @tenant_from_host == true
  end

  def redirect_www
    return unless request_label == "www"

    redirect_to "#{request.protocol}#{app_host}#{request.port_string}#{request.fullpath}",
                allow_other_host: true,
                status: :moved_permanently
  end

  def set_tenant_from_host
    slug = request_label
    return if slug.blank? || RESERVED_SUBDOMAINS.include?(slug)

    tenant = Tenant.find_by(slug: slug)
    raise ActiveRecord::RecordNotFound, "Unknown tenant" unless tenant

    Current.tenant = tenant
    @tenant_from_host = true
  end

  def active_admin_controller?
    is_a?(ActiveAdmin::BaseController)
  end

  def require_login
    return if current_user

    redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
  end

  def bind_session_tenant
    return unless current_user

    if current_user.super_admin?
      Current.user = current_user
      Current.tenant = resolve_acting_tenant
      return
    end

    if host_tenant? && current_user.tenant_id != Current.tenant.id
      reset_session
      redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
      return
    end

    Current.user = current_user
    Current.tenant ||= current_user.tenant
  end

  def resolve_acting_tenant
    tenant = Tenant.find_by(id: session[:acting_tenant_id]) if session[:acting_tenant_id].present?
    tenant ||= host_tenant? ? Current.tenant : current_user.tenant
    session[:acting_tenant_id] = tenant.id
    tenant
  end

  def set_locale
    if active_admin_controller?
      I18n.locale = :en
      return
    end

    session[:locale] = params[:locale] if User::LOCALES.include?(params[:locale].to_s)

    locale = session[:locale].presence || current_user&.locale || "fr"
    locale = "fr" unless User::LOCALES.include?(locale.to_s)
    I18n.locale = locale
  end

  def require_hq
    capability = {
      "billings" => :billing, "org_units" => :manage_org,
      "playbooks" => :playbooks, "playbook_deploy_requests" => :playbooks,
      "visits" => :visits, "hq_widgets" => :monitor,
      "vm_missions" => :compose, "ramadan" => :manage_org
    }.fetch(controller_name, :compose)
    return if hq_user? && user_allows?(capability, tenant_wide: true)

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  # Safe monitoring / escalate surfaces for area + HQ. Compose stays on require_hq.
  # Store role is always denied (no HQ board / compose leak via area capabilities).
  def require_hq_or_area(*capabilities)
    caps = Array(capabilities).presence || [ :monitor ]
    return if (hq_user? || area_user?) && caps.all? { |cap| user_allows?(cap, tenant_wide: hq_user?) }

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def authenticate_hq_admin!
    return if super_admin? || current_user&.built_in_hq?

    if current_user
      redirect_to app_root_path, alert: t("auth.hq_required")
    else
      redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
    end
  end

  def require_super_admin
    return if super_admin?

    redirect_to app_root_path, alert: t("auth.super_admin_required")
  end

  def tenant_feature?(key)
    Current.tenant&.feature?(key)
  end

  def require_feature!(key)
    return if tenant_feature?(key)

    redirect_to app_root_path, alert: t("auth.feature_disabled")
  end

  def tenant_scope
    Current.tenant
  end
end
