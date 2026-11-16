Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # All user-facing routes are prefixed with an optional locale segment (/es, /en, ...).
  scope "(:locale)", locale: /es|en|fr|de|it|pt/ do
    root "pages#home"

    # Public browsing (Phase 2b). `search` renders the same results page as
    # the listings index — it is a canonical SEO entry, not a redirect.
    resources :listings, only: %i[index show], path: "listings"
    resources :categories, only: :show, path: "c"
    resources :stores, only: :show, path: "stores"
    get "search", to: "listings#index", as: :search

    resource :session
    resources :passwords, param: :token
    resource :registration, only: %i[new create]
  end
end
