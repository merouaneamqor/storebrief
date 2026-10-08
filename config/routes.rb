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
    member do
      post :send_brief
      post :notify_push
      post :stop_recurrence
      patch :priority, action: :update_priority
    end
  end

  resources :templates, only: %i[index], controller: "checklist_templates" do
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
  resources :audit_templates
  resources :visits, only: %i[index show new create edit update] do
    collection do
      get :calendar
    end
    member do
      patch :cancel
    end
  end
  get "classement", to: "rankings#show", as: :ranking
  resource :billing, only: %i[show update]
  resource :ramadan, only: :update, controller: "ramadan"
  post "deliveries/:delivery_id/verdict", to: "delivery_verdicts#create", as: :delivery_verdict
end
