class ChecklistTemplatesController < ApplicationController
  before_action :require_hq

  def index
    @templates = tenant_scope.checklist_templates.order(:category, :title_fr)
  end

  def use
    template = tenant_scope.checklist_templates.find(params[:id])
    checklist = Checklist.build_from_template(template, author: current_user)
    checklist.save!
    redirect_to checklist_path(checklist), notice: t("checklists.draft_saved")
  end
end
