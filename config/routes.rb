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

      # Seller order fulfilment (Phase 4b): confirm a direct payment,
      # record the shipment, cancel before shipping. Scoped through
      # current_user.sales — foreign sellers 404.
      resources :sales, only: %i[index show] do
        resource :payment_confirmation, only: :create
        resource :shipment, only: :create
        resource :cancellation, only: :create
      end
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

    # Cart & checkout (Phase 4b). The cart works for guests too: their
    # cart is keyed by a signed cookie token and merged into the user's
    # cart on login. Cart item edits/teardowns are the standard plural
    # resource verbs ("Save to wishlist" is a PATCH with an intent).
    resource :cart, only: :show
    resources :cart_items, only: %i[create update destroy]

    resource :checkout, only: %i[show create] # auth required

    # Account area: shipping addresses (checkout selects one of these).
    resources :addresses, only: %i[index new create edit update destroy]

    # Buyer order pages. Lifecycle steps are nested singular resources
    # (POST creates the transition), matching the sell-area convention;
    # role guards live in the controllers (all lookups are scoped through
    # current_user.orders, so anyone else 404s).
    resources :orders, only: %i[index show] do
      resource :delivery_confirmation, only: :create
      resource :completion, only: :create
      resource :cancellation, only: :create
      resource :dispute, only: :create
      resource :review, only: %i[new create]
    end
  end

  # Stripe webhook endpoint: no locale segment, no session, CSRF-skipped
  # (Stripe authenticates via the signed payload — see the controller).
  resources :stripe_webhooks, only: :create
end
