Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  get "up" => "rails/health#show", as: :rails_health_check

  # Progressive Web App (installable on phones)
  # Pin formats so the templates resolve whatever Accept header the browser sends
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }

  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  get  "saml/:tenant_slug",          to: "saml#sso",      as: :saml_sso
  post "saml/:tenant_slug/acs",      to: "saml#acs",      as: :saml_acs
  get  "saml/:tenant_slug/metadata", to: "saml#metadata", as: :saml_metadata

  patch "locale", to: "locales#update"

  get "legal/privacy", to: "legal#privacy", as: :legal_privacy
  get "legal/cookies", to: "legal#cookies", as: :legal_cookies
  resource :privacy_preferences, only: %i[show update] do
    post :data_request, on: :member
  end

  root "marketing#show"
  post "demo_requests", to: "marketing#create_demo"
  get "resources", to: "marketing#resources"
  get "app", to: "dashboard#show", as: :app_root
  resources :tenants, only: :index do
    collection do
      post :switch
    end
  end
  resources :demo_requests, only: %i[index update]
  get "reports", to: "reports#show"

  resources :org_units, only: :index
  resources :communications, only: %i[index show new create edit update] do
    collection do
      get :preview_targets
    end
    member do
      post :send_brief
      post :notify_push
      post :stop_recurrence
      post :save_as_template
      post :clear_dependency
      patch :priority, action: :update_priority
    end
  end

  resources :task_templates, only: %i[index new create edit update destroy], controller: "communication_templates" do
    member do
      post :use
    end
  end

  resources :templates, only: %i[index new create edit update destroy], controller: "checklist_templates" do
    member do
      post :use
    end
  end


  namespace :checklists do
    resources :deliveries, only: %i[index show], controller: "/checklist_deliveries" do
      member do
        post :submit_item
        post :complete
      end
    end
  end

  resources :checklists, only: %i[index show] do
    member do
      post :send_checklist
      post :notify_push
      post :stop_recurrence
    end
  end

  post "sync/checklist_responses", to: "sync#checklist_responses"

  get "push/vapid_public_key", to: "push_subscriptions#vapid_public_key"
  resource :push_subscription, only: %i[create destroy]

  resources :my_tasks, only: %i[index show]
  resources :inbox, only: %i[index show], controller: "inbox" do
    member do
      post :complete
      post :advance
    end
  end

  resources :playbooks, only: %i[index new create edit update destroy] do
    collection do
      get :campaigns
    end
    member do
      post :deploy
      get :preview
      post :reset
    end
  end
  resources :visits, only: %i[index show new create edit update] do
    collection do
      get :calendar
    end
    member do
      patch :cancel
    end
  end
  resource :audit_history, only: :show
  resources :stores, only: :show
  get "classement", to: "rankings#show", as: :ranking
  resource :billing, only: %i[show update]
  resource :ramadan, only: :update, controller: "ramadan"
  post "deliveries/:delivery_id/verdict", to: "delivery_verdicts#create", as: :delivery_verdict
  post "deliveries/:delivery_id/corrective_action", to: "corrective_actions#create", as: :delivery_corrective_action
  post "deliveries/:delivery_id/clear_dependency", to: "delivery_dependencies#clear", as: :delivery_clear_dependency
  patch "deliveries/:delivery_id/reassign", to: "delivery_dependencies#reassign", as: :delivery_reassign
  post "checklist_item_responses/:checklist_item_response_id/corrective_action",
       to: "corrective_actions#create", as: :checklist_item_corrective_action
end
