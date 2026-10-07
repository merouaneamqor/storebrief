class BriefTemplatesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:briefs) }
  before_action :set_template, only: %i[use destroy]

  def index
    @templates = tenant_scope.brief_templates.ordered
  end

  def use
    brief = @template.build_communication(author: current_user)
    brief.save!
    redirect_to edit_communication_path(brief), notice: t("brief_templates.draft_created")
  end

  def destroy
    @template.destroy
    redirect_to brief_templates_path, notice: t("brief_templates.deleted")
  end

  private

  def set_template
    @template = tenant_scope.brief_templates.find(params[:id])
  end
end
