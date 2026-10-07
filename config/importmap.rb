# Pin npm packages by running ./bin/importmap

pin "application"
pin "offline_sync"
pin "brief_form"
pin "campaign_targets"
pin "audit_template_form"
pin "pwa_install"
pin "pwa_push"
pin "task_lang"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
