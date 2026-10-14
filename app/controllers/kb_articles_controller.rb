class KbArticlesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_feature!(:knowledge_base) }
  before_action :set_article, only: %i[show edit update destroy publish archive unpublish]
  before_action :load_form_options, only: %i[new create edit update]

  def index
    @state = params[:state].presence_in(KbArticle::PUBLISH_STATES)
    @category = tenant_scope.kb_categories.find_by(id: params[:kb_category_id]) if params[:kb_category_id].present?
    @articles = tenant_scope.kb_articles.includes(:kb_category, :author).ordered
    @articles = @articles.with_state(@state) if @state
    @articles = @articles.where(kb_category_id: @category.id) if @category
    @categories = KbCategory.tree_for(tenant_scope)
  end

  def show
    @versions = @article.kb_article_versions.newest_first
  end

  def new
    @article = tenant_scope.kb_articles.new(
      kb_category_id: params[:kb_category_id],
      publish_state: "draft",
      version: 1
    )
  end

  def create
    @article = tenant_scope.kb_articles.new(article_attrs.merge(author: current_user))

    if @article.save
      sync_publish_snapshot!
      redirect_to kb_article_path(@article), notice: t("morocco.kb.articles.saved", title: @article.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @article.update(article_attrs)
      sync_publish_snapshot!
      redirect_to kb_article_path(@article), notice: t("morocco.kb.articles.saved", title: @article.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @article.title
    @article.destroy!
    redirect_to kb_articles_path, notice: t("morocco.kb.articles.deleted", title: title)
  end

  def publish
    @article.publish!(by: current_user)
    redirect_to kb_article_path(@article), notice: t("morocco.kb.articles.published", title: @article.title, version: @article.version)
  end

  def archive
    @article.archive!
    redirect_to kb_article_path(@article), notice: t("morocco.kb.articles.archived", title: @article.title)
  end

  def unpublish
    @article.unpublish!
    redirect_to kb_article_path(@article), notice: t("morocco.kb.articles.unpublished", title: @article.title)
  end

  private

  def set_article
    @article = tenant_scope.kb_articles.find(params[:id])
  end

  def load_form_options
    @category_options = KbCategory.options_for_select(tenant_scope)
  end

  def article_attrs
    params.require(:kb_article).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :kb_category_id, :publish_state
    )
  end

  # Creating/updating as published records a version when content is new or changed.
  def sync_publish_snapshot!
    return unless @article.published?

    last = @article.kb_article_versions.order(:version).last
    if last.blank?
      @article.publish!(by: current_user)
      return
    end

    changed = last.title_fr != @article.title_fr ||
              last.title_ar.to_s != @article.title_ar.to_s ||
              last.body_fr.to_s != @article.body_fr.to_s ||
              last.body_ar.to_s != @article.body_ar.to_s
    @article.publish!(by: current_user) if changed
  end
end
