# frozen_string_literal: true

class HqWidgetsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }

  def show
    @widgets = tenant_scope.hq_widgets
  end

  def update
    tenant_scope.hq_widgets = widget_params
    if tenant_scope.save
      redirect_to hq_widgets_path, notice: t("morocco.hq.widgets.saved")
    else
      @widgets = tenant_scope.hq_widgets
      flash.now[:alert] = tenant_scope.errors.full_messages.to_sentence.presence || t("morocco.hq.widgets.save_failed")
      render :show, status: :unprocessable_entity
    end
  end

  private

  def widget_params
    raw = params.fetch(:hq_widgets, {}).permit(*Tenant::HQ_WIDGETS.keys)
    Tenant::HQ_WIDGETS.keys.index_with { |key| raw[key].present? && raw[key] != "0" }
  end
end
