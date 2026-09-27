Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  patch "locale", to: "locales#update"

  root "dashboard#show"

  resources :org_units, only: :index
  resources :communications, only: %i[index show new create] do
    member do
      post :send_brief
    end
  end

  resources :templates, only: %i[index], controller: "checklist_templates" do
    member do
      post :use
    end
  end

  resources :checklists, only: %i[index show] do
    member do
      post :send_checklist
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

  post "sync/checklist_responses", to: "sync#checklist_responses"

  resources :inbox, only: %i[index show], controller: "inbox" do
    member do
      post :complete
    end
  end
end
