class LocalesController < ApplicationController
  skip_before_action :require_login, only: :update

  def update
    locale = params[:locale].to_s
    locale = "fr" unless User::LOCALES.include?(locale)
    session[:locale] = locale
    current_user&.update!(locale: locale)

    redirect_back fallback_location: root_path
  end
end
