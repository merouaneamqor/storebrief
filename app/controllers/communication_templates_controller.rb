class CommunicationTemplatesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:briefs) }
  before_action :set_template, only: %i[edit update destroy use]

  def index
    @templates = tenant_scope.communication_templates.order(:title_fr)
  end

  def new
    @template = tenant_scope.communication_templates.new(
      format: "task",
      priority: Communication::DEFAULT_PRIORITY,
      questions: []
    )
  end

  def create
    @template = tenant_scope.communication_templates.new(template_attrs)

    if @template.save
      redirect_to task_templates_path, notice: t("task_templates.saved", title: @template.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_attrs)
      redirect_to task_templates_path, notice: t("task_templates.saved", title: @template.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @template.title
    @template.destroy!
    redirect_to task_templates_path, notice: t("task_templates.deleted", title: title)
  end

  def use
    communication = Communication.build_from_template(@template, author: current_user)
    communication.save!
    redirect_to edit_communication_path(communication), notice: t("communications.draft_saved")
  end

  private

  def set_template
    @template = tenant_scope.communication_templates.find(params[:id])
  end

  def template_attrs
    permitted = params.require(:communication_template).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :format, :requires_proof, :requires_approval, :priority,
      questions: [
        :position, :question_type, :title_fr, :title_ar, :required,
        { options: %i[label_fr label_ar] }
      ]
    )
    permitted[:questions] = CommunicationTemplate.normalize_questions(permitted[:questions])
    permitted[:requires_proof] = ActiveModel::Type::Boolean.new.cast(permitted[:requires_proof])
    permitted[:requires_approval] = ActiveModel::Type::Boolean.new.cast(permitted[:requires_approval])
    permitted
  end
end
