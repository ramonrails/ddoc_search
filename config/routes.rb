Rails.application.routes.draw do
  # API v1 routes
  scope "/v1" do
    resources :documents, only: [ :create, :show, :destroy ]
    get "/search", to: "search#index"
  end

  # Health check (no authentication required)
  get "/health", to: "health#show"

  # Keep default Rails health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Default route
  root to: proc { [ 404, {}, [ "Not Found" ] ] }
end
