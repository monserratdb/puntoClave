Rails.application.routes.draw do
  root "home#index"
  
  get "predict", to: "predictions#index"
  get "players", to: "predictions#players" 
  get "matches", to: "predictions#matches"
  
  resources :predictions, only: [:index, :show] do
    collection do
      post :predict
      get :admin
      post :scrape_data
      get :players
      get :matches
    end
    member do
      get :future_matches
    end
  end
  
  resources :players, only: [:index, :show]
  resources :matches, only: [:index, :show]
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
