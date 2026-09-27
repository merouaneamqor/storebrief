Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  root "dashboard#show"

  resources :org_units, only: :index
  resources :communications, only: %i[index show new create] do
    member do
      post :send_brief
    end
  end

  resources :inbox, only: %i[index show], controller: "inbox" do
    member do
      post :complete
    end
  end
end
