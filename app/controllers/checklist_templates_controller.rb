class ChecklistTemplatesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:checklists) }
  before_action :set_template, only: %i[edit update destroy use]

  def index
    @templates = tenant_scope.checklist_templates.order(:category, :title_fr)
  end

  def new
    @template = tenant_scope.checklist_templates.new(
      category: "store_visit",
      items: [
        {
          "type" => "section",
          "key" => "section_1",
          "title_fr" => "",
          "title_ar" => ""
        },
        {
          "type" => "question",
          "key" => "question_1",
          "title_fr" => "",
          "title_ar" => "",
          "required" => true,
          "requires_photo" => false
        }
      ]
    )
  end

  def create
    @template = tenant_scope.checklist_templates.new(template_attrs)

    if @template.save
      redirect_to templates_path, notice: t("templates.saved", title: @template.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_attrs)
      redirect_to templates_path, notice: t("templates.saved", title: @template.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @template.title
    @template.destroy!
    redirect_to templates_path, notice: t("templates.deleted", title: title)
  end

  def use
    checklist = Checklist.build_from_template(@template, author: current_user)
    checklist.save!
    redirect_to checklist_path(checklist), notice: t("checklists.draft_saved")
  end

  private

  def set_template
    @template = tenant_scope.checklist_templates.find(params[:id])
  end

  def template_attrs
    permitted = params.require(:checklist_template).permit(
      :category, :title_fr, :title_ar, :description_fr, :description_ar,
      items: [
        :type, :key, :question_type, :weight, :title_fr, :title_ar, :required, :requires_photo,
        { show_if: %i[question_key equals] }
      ]
    )
    permitted[:items] = ChecklistTemplate.normalize_items(permitted[:items])
    permitted
  end
end
