class KbCategoriesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_feature!(:knowledge_base) }
  before_action :set_category, only: %i[edit update destroy]
  before_action :load_parent_options, only: %i[new create edit update]

  def index
    @tree = KbCategory.tree_for(tenant_scope)
  end

  def new
    @category = tenant_scope.kb_categories.new(parent_id: params[:parent_id], position: 0)
  end

  def create
    @category = tenant_scope.kb_categories.new(category_attrs)

    if @category.save
      redirect_to kb_categories_path, notice: t("morocco.kb.categories.saved", title: @category.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_attrs)
      redirect_to kb_categories_path, notice: t("morocco.kb.categories.saved", title: @category.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @category.title
    if @category.destroy
      redirect_to kb_categories_path, notice: t("morocco.kb.categories.deleted", title: title)
    else
      redirect_to kb_categories_path, alert: t("morocco.kb.categories.cannot_delete", title: title)
    end
  end

  private

  def set_category
    @category = tenant_scope.kb_categories.find(params[:id])
  end

  def load_parent_options
    exclude = @category if defined?(@category) && @category&.persisted?
    @parent_options = KbCategory.options_for_select(tenant_scope, exclude: exclude)
  end

  def category_attrs
    params.require(:kb_category).permit(
      :title_fr, :title_ar, :description_fr, :description_ar, :parent_id, :position
    )
  end
end
