class AuditTemplatesController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_template_reader
  before_action :require_hq, except: %i[index show]
  before_action :set_template, only: %i[show edit update destroy]

  def index
    @templates = tenant_scope.audit_templates.order(:title_fr)
  end

  def show; end

  def new
    @template = tenant_scope.audit_templates.new
  end

  def create
    @template = tenant_scope.audit_templates.new(template_attrs)
    if @template.save
      redirect_to audit_template_path(@template), notice: t("morocco.audit_templates.saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @template.update(template_attrs)
      redirect_to audit_template_path(@template), notice: t("morocco.audit_templates.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    redirect_to audit_templates_path, notice: t("morocco.audit_templates.deleted")
  end

  private

  def require_template_reader
    return if hq_user? || current_user.area?

    redirect_to app_root_path, alert: t("morocco.visits.access_required")
  end

  def set_template
    @template = tenant_scope.audit_templates.find(params[:id])
  end

  def template_attrs
    source = params.require(:audit_template)
    {
      title_fr: source[:title_fr],
      title_ar: source[:title_ar],
      description_fr: source[:description_fr],
      description_ar: source[:description_ar],
      sections: AuditTemplate.normalize_sections(source[:sections])
    }
  end
end
