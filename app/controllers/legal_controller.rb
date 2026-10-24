# frozen_string_literal: true

class LegalController < ApplicationController
  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  layout "marketing"

  def privacy
  end

  def cookies
  end
end
