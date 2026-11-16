Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # All user-facing routes are prefixed with an optional locale segment (/es, /en, ...).
  scope "(:locale)", locale: /es|en|fr|de|it|pt/ do
    root "pages#home"

    resource :session
    resources :passwords, param: :token
    resource :registration, only: %i[new create]
  end
end
