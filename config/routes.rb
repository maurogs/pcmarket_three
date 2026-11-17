Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # All user-facing routes are prefixed with an optional locale segment (/es, /en, ...).
  scope "(:locale)", locale: /es|en|fr|de|it|pt/ do
    root "pages#home"

    # Trust & Safety and static content pages (Phase 7b). Slugs are
    # whitelisted in the controllers; unknown ones 404. Public legal pages
    # resolve (country, locale) → en → country default locale in
    # LegalPagesController.
    resource :trust, only: :show, path: "trust-and-safety"
    resources :pages, only: :show, param: :slug
    resources :legal_pages, only: :show, param: :slug, path: "legal"
    resources :contact_messages, only: %i[create]

    # Public browsing (Phase 2b). `search` renders the same results page as
    # the listings index — it is a canonical SEO entry, not a redirect.
    resources :listings, only: %i[index show], path: "listings"
    resources :categories, only: :show, path: "c"
    resources :stores, only: :show, path: "stores"
    get "search", to: "listings#index", as: :search

    # PC Finder (Phase 7a): the quiz form GETs to the results page, which is
    # a plain index over published gaming PCs (see PcFinder::Search).
    resource :pc_finder, only: :show, path: "pc-finder"
    resources :pc_finder_results, only: :index, path: "pc-finder/results"

    # "Sell to us" trade-in (Phase 7a, behind the :sell_to_us flag — see the
    # controllers). Quotes are created anonymously; accepting one is a nested
    # singular resource POST (state transition), matching the listing status
    # convention used in the sell area.
    resources :trade_in_quotes, only: %i[new create show], path: "sell-to-us" do
      resource :acceptance, only: :create, controller: "trade_in_acceptances"
    end

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
      # "Report this listing" (Phase 7b): signed-in users only; one OPEN
      # report per user per listing (see Report).
      resources :reports, only: %i[new create]
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

    # Favourites / wishlist (Phase 5). create/destroy are Turbo Stream calls
    # from listing cards and the listing page; index is the wishlist itself.
    resources :favorites, only: %i[index create destroy]

    # Saved searches (max 25 per user, enforced in the model; update
    # toggles email_alerts).
    resources :saved_searches, only: %i[index create update destroy]

    # Notification centre. Mark-all-read is a singular resource (POST
    # creates the "read everything" action), matching the project's
    # state-transition convention.
    resources :notifications, only: :index
    resource :notifications_read, only: :create

    # Account settings (Phase 5): profile, security, notification
    # preferences, GDPR export and deletion. Singular resources because
    # each one is "the current user's" thing.
    namespace :account do
      resource :profile, only: %i[show update]
      resource :security, only: %i[show update]
      resource :notification_preferences, only: %i[show update]
      resource :data_export, only: :create
      resource :deletion, only: %i[show destroy]
    end

    # Following a store (Phase 5): POST/DELETE on a nested singular
    # resource, matching the state-transition convention.
    resources :stores, only: [] do
      resource :follow, only: %i[create destroy]
    end

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

    # Admin area (Phase 6a). Non-admins 404 on every route (see
    # Admin::BaseController — a 403 would confirm the panel exists).
    # Moderation steps are nested singular resources on listings (POST
    # creates the transition), matching the project convention; the
    # impersonation `destroy` is reachable while impersonating because its
    # controller skips the admin guard for that one verb.
    namespace :admin do
      root to: "dashboards#show"

      resource :dashboard, only: :show
      resource :search, only: :show

      # Moderation queue (oldest pending first).
      resources :moderations, only: %i[index show]

      resources :listings, only: %i[index show edit update destroy] do
        resource :approval, only: :create
        resource :rejection, only: %i[new create]
        resource :unpublication, only: :create
      end
      resource :bulk_moderation, only: :create

      resources :users, only: %i[index show edit update] do
        resource :ban, only: %i[new create destroy]
        resource :impersonation, only: %i[create destroy]
      end

      resources :stores, only: %i[index show edit update] do
        resource :verification, only: %i[create destroy]
        resource :hiding, only: %i[create destroy]
      end

      # Orders & disputes (Phase 6b). The order `update` is the audited
      # forced status transition; internal notes are nested rows. The
      # dispute resolution form is a nested singular resource (POST creates
      # the outcome), matching the project's state-transition convention.
      resources :orders, only: %i[index show update] do
        resources :notes, only: %i[create destroy]
      end
      resources :disputes, only: %i[index show] do
        resource :resolution, only: %i[new create]
      end

      # Review moderation: DELETE hides (sets hidden_at) with a reason.
      resources :reviews, only: %i[index destroy]

      # Taxonomy (Phase 6b). Category ordering uses up/down buttons posting
      # to the nested singular :position resource (swap with the adjacent
      # sibling). Spec attributes are attached to categories through the
      # nested collection (CategorySpecAttribute join rows).
      resources :categories do
        resource :position, only: :create
        resources :spec_attributes, only: %i[index create update destroy],
                  controller: "category_spec_attributes"
      end
      resources :spec_attributes, except: :show do
        resources :spec_options, only: %i[create update destroy] do
          resource :merge, only: :create, controller: "spec_option_merges"
        end
        resource :bulk_option, only: :create
      end
      resources :labels, except: :show
      resources :seller_tags, except: :show

      # Platform settings: countries launch toggles, feature flags (Flipper),
      # site settings, legal pages, newsletter list and the audit log browse.
      resources :countries, only: %i[index edit update]
      resources :feature_flags, only: %i[index update]
      resources :trade_ins, only: %i[index show update]

      # Listing reports inbox (Phase 7b). Closing a report is a nested
      # singular resource (POST creates the outcome), matching the
      # state-transition convention; both are audited.
      resources :reports, only: %i[index show] do
        resource :resolution, only: :create, controller: "report_resolutions"
        resource :dismissal, only: :create, controller: "report_dismissals"
      end
      resources :contact_messages, only: %i[index show]
      resource :settings, only: %i[edit update]
      resources :legal_pages
      resources :newsletter_subscriptions, only: %i[index destroy]
      resources :audit_logs, only: :index
    end
  end

  # Stripe webhook endpoint: no locale segment, no session, CSRF-skipped
  # (Stripe authenticates via the signed payload — see the controller).
  resources :stripe_webhooks, only: :create

  # Non-resource exceptions to the locale scoping (legitimate: fixed,
  # machine-readable paths that must live at the domain root):
  #
  # * robots.txt is served dynamically (see RobotsController) so the
  #   rules follow the search_engine_indexing setting and the
  #   environment; a static public/robots.txt would shadow the route,
  #   which is why it was deleted.
  get "robots.txt" => "robots#show"

  # Localized error pages: config.exceptions_app = routes re-dispatches
  # 404/422/500 to these paths (ShowExceptions rewrites PATH_INFO to the
  # status code), and ErrorsController recovers the locale from the
  # original request path.
  get "/404" => "errors#not_found"
  get "/422" => "errors#unprocessable"
  get "/500" => "errors#internal_server_error"
end
