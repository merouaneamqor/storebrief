class RankingsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }

  def show
    @ranking = Vazivo::Ranking.for(tenant_scope)
  end
end
