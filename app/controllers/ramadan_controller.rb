class RamadanController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }

  def update
    tenant_scope.update!(ramadan_mode: !tenant_scope.ramadan_mode?)
    key = tenant_scope.ramadan_mode? ? "morocco.ramadan.on" : "morocco.ramadan.off"
    redirect_back fallback_location: app_root_path, notice: t(key, open: tenant_scope.effective_open)
  end
end
