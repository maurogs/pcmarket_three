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

    # Seller area (Phase 3a/3b): listing create/edit, review submission,
    # archiving and mark-sold, plus the Phase 3b dashboard, store settings,
    # vacation toggle and sales. Status changes are modelled as nested
    # singular resources (POST creates a state transition) instead of custom
    # member actions.
    namespace :sell do
      # The dashboard is the landing page of the sell area (/sell).
      root to: "dashboards#show", as: :sell_root

      resource :dashboard, only: :show

      resources :listings do
        resource :submission, only: :create
        resource :archival, only: :create
        resource :sale_mark, only: :create
      end
      resources :category_fields, only: :show

      resource :store, only: %i[edit update]
      resource :vacation, only: %i[create destroy]
      resources :sales, only: %i[index show]
    end

    # Messaging & offers (Phase 4a). Status changes on offers are modelled
    # as nested singular resources (POST creates the decision), matching the
    # sell-area convention — no custom member actions.
    resources :conversations, only: %i[index show create] do
      resources :messages, only: :create
      resource :read_receipt, only: :create
    end
    resources :blocks, only: %i[index create destroy]

    resources :listings, only: [] do
      resources :offers, only: %i[new create]
    end
    resources :offers, only: :index
    resources :offers, only: [] do
      resource :acceptance, only: :create
      resource :decline, only: :create
      resource :withdrawal, only: :create
    end
  end
end
