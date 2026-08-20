Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  # The one endpoint this whole app exists for: a client posts a transcript
  # here and gets back Claude's reply plus any actions to run locally.
  # Namespacing under "api" keeps the door open for other endpoints later
  # (e.g. fetching conversation history) without them colliding with routes
  # like /up above.
  namespace :api do
    post "command", to: "commands#create"
  end
end
