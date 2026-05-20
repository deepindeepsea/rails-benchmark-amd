Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by uptime monitors and load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"

  # Benchmark routes for testing different response types
  get "hello", to: "home#hello"
  get "json", to: "home#json"
  get "data", to: "home#data"

  # Simple endpoint for pure text response
  get "ping", to: "home#ping"

  # Health check endpoint
  get "health", to: "home#health"
end