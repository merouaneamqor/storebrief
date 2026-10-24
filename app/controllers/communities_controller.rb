class CommunitiesController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_feature!(:communities) }
  before_action :load_community, only: [ :show, :destroy, :create_post, :create_comment, :destroy_post, :destroy_comment ]

  def index
    @communities = tenant_scope.communities.includes(:org_unit).order(:title_fr).select { |community| community.readable_by?(current_user) }
    @community = tenant_scope.communities.new
    @regions = tenant_scope.org_units.regions.select { |region| user_allows?(:manage_communities, org_unit: region) }
    @can_create = @regions.any? || user_allows?(:manage_communities, tenant_wide: true)
  end

  def create
    attributes = params.require(:community).permit(:title_fr, :title_ar, :audience_role)
    community = tenant_scope.communities.new(attributes)
    region_id = params[:community][:org_unit_id].presence
    community.org_unit = tenant_scope.org_units.regions.find(region_id) if region_id
    unless community.manageable_by?(current_user)
      head :forbidden
      return
    end
    if community.save
      redirect_to community
    else
      redirect_to communities_path, alert: community.errors.full_messages.to_sentence
    end
  end

  def show
    @page = [ params[:page].to_i, 1 ].max
    @posts = @community.community_posts.includes(:user).order(created_at: :desc, id: :desc).offset((@page - 1) * 20).limit(21).to_a
    @more = @posts.length > 20
    @posts = @posts.first(20)
  end

  def create_post
    save_discussion(@community.community_posts.new(user: current_user, body: params[:body]))
  end

  def create_comment
    post = @community.community_posts.find(params[:post_id])
    save_discussion(post.community_comments.new(user: current_user, body: params[:body]))
  end

  def destroy_post
    return head :forbidden unless @community.manageable_by?(current_user)

    @community.community_posts.find(params[:post_id]).destroy!
    redirect_to @community
  end

  def destroy_comment
    return head :forbidden unless @community.manageable_by?(current_user)

    @community.community_posts.find(params[:post_id]).community_comments.find(params[:comment_id]).destroy!
    redirect_to @community
  end

  def destroy
    return head :forbidden unless @community.manageable_by?(current_user)

    @community.destroy!
    redirect_to communities_path
  end

  private

  def load_community
    @community = tenant_scope.communities.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @community.readable_by?(current_user)
  end

  def save_discussion(record)
    flash[:alert] = record.errors.full_messages.to_sentence unless record.save
    redirect_to @community
  end
end
