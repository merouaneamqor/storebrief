class KbArticlesController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_feature!(:knowledge_base) }
  before_action :require_hq, except: %i[index show]
  before_action :require_kb_reader, only: %i[index show]
  before_action :set_article, only: %i[show edit update destroy publish archive unpublish]
  before_action :load_form_options, only: %i[new create edit update]

  def index
    @q = params[:q].to_s.strip
    @role_filter = resolve_role_filter
    @search_mode = @q.present? || !hq_user? || params[:role].present?

    if hq_user? && !@search_mode
      @state = params[:state].presence_in(KbArticle::PUBLISH_STATES)
      @category = tenant_scope.kb_categories.find_by(id: params[:kb_category_id]) if params[:kb_category_id].present?
      @articles = tenant_scope.kb_articles.includes(:kb_category, :author).ordered
      @articles = @articles.with_state(@state) if @state
      @articles = @articles.where(kb_category_id: @category.id) if @category
      @categories = KbCategory.tree_for(tenant_scope)
    else
      result =
        if hq_user?
          Vazivo::KbSearch.call(
            tenant: tenant_scope,
            query: @q,
            role: @role_filter,
            store_tags: nil,
            published_only: false,
            bypass_access: @role_filter.blank?
          )
        else
          Vazivo::KbSearch.call(
            tenant: tenant_scope,
            query: @q,
            user: current_user,
            published_only: true
          )
        end
      @articles = result.articles
      @categories = KbCategory.tree_for(tenant_scope) if hq_user?
    end
  end

  def show
    @versions = @article.kb_article_versions.newest_first if hq_user?
    return if hq_user?
    return if @article.published? && Vazivo::KbAccess.allowed?(@article, user: current_user)

    redirect_to kb_articles_path, alert: t("morocco.kb.search.unavailable")
  end

  def new
    @article = tenant_scope.kb_articles.new(
      kb_category_id: params[:kb_category_id],
      publish_state: "draft",
      version: 1,
      audience_roles: [],
      audience_store_tags: []
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

  def require_kb_reader
    return if hq_user? || area_user? || store_user?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def set_article
    @article = tenant_scope.kb_articles.find(params[:id])
  end

  def load_form_options
    @category_options = KbCategory.options_for_select(tenant_scope)
    @store_tag_options = tenant_store_tag_options
  end

  def article_attrs
    attrs = params.require(:kb_article).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :kb_category_id, :publish_state,
      audience_roles: [], audience_store_tags: []
    )
    attrs[:audience_roles] = Array(attrs[:audience_roles]).reject(&:blank?) if attrs.key?(:audience_roles)
    if attrs.key?(:audience_store_tags)
      attrs[:audience_store_tags] = Array(attrs[:audience_store_tags]).reject(&:blank?)
    end
    attrs
  end

  # Store/area are locked to their role. HQ may preview any role or all.
  def resolve_role_filter
    return viewer_role unless hq_user?

    params[:role].to_s.presence_in(Membership::ROLES)
  end

  def viewer_role
    if hq_user?
      "hq"
    elsif area_user?
      "area"
    elsif store_user?
      "store"
    end
  end

  def tenant_store_tag_options
    stores = tenant_scope.org_units.stores
    (
      stores.where.not(store_format: [ nil, "" ]).distinct.pluck(:store_format) +
      stores.where.not(cluster_key: [ nil, "" ]).distinct.pluck(:cluster_key)
    ).map(&:to_s).uniq.sort
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
