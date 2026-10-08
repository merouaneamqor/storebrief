# frozen_string_literal: true

aa_styles = Gem.loaded_specs["activeadmin"].full_gem_path + "/app/assets/stylesheets"

Rails.application.config.dartsass.builds = {
  "application.scss" => "application.css",
  "marketing.scss" => "marketing.css",
  "active_admin.scss" => "active_admin.css"
}

Rails.application.config.dartsass.build_options << "--load-path=#{aa_styles}"
