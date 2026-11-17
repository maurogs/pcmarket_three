# PCMarket — Project Context

## Purpose

Marketplace for new and second-hand PC hardware (GPUs, CPUs, laptops, components).
Phase 0 built the foundation (auth, i18n, Tailwind chrome), Phase 1 the domain layer,
Phase 2a the reference-data seeds, Phase 2b **public browsing** — search results,
category pages, listing pages and seller storefronts, all read-only — Phase 3a
**seller listing management** (authenticated sellers create/edit their listings, photo
upload, review submission, archiving, mark-sold), Phase 3b **seller dashboard &
store settings** (`/sell` dashboard with KPIs and a 12-week chart, store settings with
Spanish tax-ID validation and FriendlyId slug history, vacation mode, read-only sales
list), and Phase 4a **internal chat & offers** (buyer↔seller threads with Turbo
real-time, read receipts, blocks, offer negotiation with 48h expiry and
accept-to-reserve, all I18n'd). Cart/checkout and the admin/moderation
UI come in later phases.

## Stack

- Rails 8.1, Ruby 4.0 (see `.ruby-version`), PostgreSQL (pg)
- Hotwire: Turbo + Stimulus, importmap-rails (no bundler for JS)
- Tailwind CSS v4 via `tailwindcss-rails` (source: `app/assets/tailwind/application.css`, built to `app/assets/builds/tailwind.css`)
- Propshaft, Puma, Solid Queue/Cache/Cable, Kamal, Thruster
- Auth: Rails-generated `authentication` generator (session cookie → `Session` model, `has_secure_password`)

## Decisions

- **Brand**: "PCMarket". Single source of truth is the i18n key `site.name`
  (a configurable `Setting` model will replace the fallback later).
- **Launch**: Spain only. `users.country_code` defaults to `"ES"`; future country
  toggles: FR, GB, DE, IT, PT. No multi-country logic yet.
- **Feature flags** (Flipper + ActiveRecord adapter, tables `flipper_features`/`flipper_gates`,
  config in `config/initializers/flipper.rb`). All **OFF by default**:
  `commissions`, `featured_listings`, `stripe_checkout`, `sell_to_us`, `google_login`.
- **Listings require admin approval** before being public (enforced in the listings phase;
  `users.role` enum admin:1 exists already).
- **API**: will live at `/api/v1` (not routed yet).
- **I18n**: `available_locales = [:es, :en, :fr, :de, :it, :pt]`, default `:es`,
  fallbacks `[:en]`. Every route is wrapped in `scope "(:locale)"` (except the `/up`
  health check). `ApplicationController#switch_locale` picks
  `params[:locale] || current user locale || :es` and `default_url_options` injects the
  current locale into every generated path.
  - **Never hardcode user-facing strings.** All copy lives in `config/locales/*.yml`.
    All 6 files must keep an identical key tree — verify with `ruby script/lint_locale_keys.rb`.
    `en` is British English.
- **Tests hit /en paths**: `test/test_helper.rb` sets
  `Rails.application.routes.default_url_options[:locale] = :en` so integration helpers
  build locale-correct URLs (and positional args like `password_path(token)` bind to
  `:token`, not the optional `:locale` segment).
- **Theme**: design tokens are CSS variables in `app/assets/tailwind/application.css`
  (`:root` light, `.dark` overrides); dark mode is the Tailwind v4 `class` strategy,
  toggled client-side by `theme_controller.js` (localStorage + `prefers-color-scheme`).
- **Rack::Attack**: coarse IP throttle on POST /session (Rails `rate_limit` covers the
  login/password forms themselves).
- **Domain (Phase 1)**: listings are moderation-gated through the `Listing` status
  state machine (`submit_for_review!` → `approve!(admin)` / `reject!(reason, admin:)`;
  invalid transitions raise `Listing::InvalidTransition`). Search uses a Postgres
  tsvector column + trigger + GIN index (`Listing.search_text`), not pg_search's
  dsearch. Money is integer cents columns wrapped by the `Money` value object
  (`Listing#price`, order totals). Order numbers come from a Postgres sequence.
  `Setting.get/set` is the config store (Rails.cache-backed); feature flags stay
  in Flipper. Because of the tsvector trigger the schema is dumped as SQL:
  `schema_format: sql` in `config/database.yml` → `db/structure.sql` (pg_dump);
  never hand-edit it, `db/schema.rb` is gone.

- **Seeds (Phase 2a)**: `db/seeds.rb` `load`s one loader per concern under
  `db/seeds/` (order: countries_settings, categories, spec_attributes,
  labels_seller_tags; support module `SeedLoader` is `require`d). Idempotent
  upserts by slug / key / (attribute, value) / (category, attribute); raw data
  lives in `db/seeds/data/*.yml` for admins — every name in all 6 locales
  (proper nouns share one `display` string, translated labels use `names`).
  Spec attributes attach to categories via `CategorySpecAttribute`
  (`required` flags: gpu_chipset→gpus, cpu_brand→cpus) and children inherit.

- **Public browsing (Phase 2b)** — read-only, no auth required:
  - Routes: `resources :listings, only: %i[index show]`, `resources :categories, only: :show,
    path: "c"`, `resources :stores, only: :show`, plus `get "search" → listings#index`
    (a canonical results page, **never** a redirect). All inside `scope "(:locale)"`.
  - **All querying lives in `ListingSearch`** (`app/services/listing_search.rb`): skinny
    controllers just build params and call it. Returns a `Result` struct
    (`records, pagy, total_count, facets, facet_attributes, filters`) with `#empty?`,
    `#facet_count`, `#spec_facets`, `#applied_filters?`. Facet counts come from **one**
    SQL query (`WITH scoped AS (…) UNION ALL` over condition::text, label/tag joins by
    slug and `jsonb_each`/`jsonb_array_elements_text` for specs) computed **before**
    pagination, so counts never track the current page. `category` = self + descendants
    (unknown slug → `none`), `min_eur`/`max_eur` → cents, `condition[]`, `f[attr][]`
    (OR within an attribute, AND across attributes, arrays matched element-wise),
    `labels[]`, `tags[]`, `seller` (store slug), `sort` in
    `best_match|newest|price_asc|price_desc|most_favorited`, `page`.
    Featured-first ordering only when `Flipper.enabled?(:featured_listings)`.
  - **Eager loading / N+1**: cards render through `Listing#with_card_data` (store, photos,
    labels, tags); controller tests assert the `sql.active_record` notification count
    stays flat when the result set grows.
  - **Pagination**: pagy 43 has **no railtie** in this app, so `include Pagy::Method` in
    `ApplicationController` and `ListingSearch` builds `Pagy::Offset.new` explicitly
    (nav via `results_pagination` helper → `raw(pagy.series_nav)`); `Pagy::I18n.locale`
    is set in `switch_locale`. No `pagy.*` keys in the app locale files. 24 per page.
  - **Filtering is a Turbo Frame**: one `<form method="get" data-turbo-frame="results"
    data-controller="filters">` wraps the sidebar and `<turbo-frame id="results"
    data-turbo-action="advance">`, so applying a filter re-renders only `#results`
    (`listings/_browse`, `_filters`, `_results` are shared by index / category / store
    pages). The mobile filter sheet is a `<dialog>` (`.filters-sheet` in the Tailwind CSS).
  - **Caching**: fragment caching on (`:memory_store` in dev, `:solid_cache_store` in
    prod, `:null_store` in test) with Russian-doll cards —
    `cache [I18n.locale, "listing_card", …, listing]` in `shared/_listing_card`; the
    header mega menu + mobile menu fragments are cached per locale and busted by
    `Category.maximum(:updated_at)`; show/store pages use `fresh_when(etag:, last_modified:,
    public: <anonymous AND publicly visible>, private: otherwise)` — only anonymous hits on
    publicly visible records may enter a shared cache, because the header is personalised
    and owners/admins see unpublished listings (verified 304 on `If-None-Match`).
  - **Images**: `Listing::PHOTO_VARIANTS` = `card` (webp 400×400) and `gallery`
    (webp 1200×1200); helpers always emit `loading="lazy" decoding="async"` plus explicit
    `width`/`height` (CLS-free), with an SVG placeholder when a listing has no photos.
  - **Visibility**: `Listing.published == where(status: :approved)`; show allows
    `approved`/`sold`/`reserved` to everyone and everything else to owner/admin only.
    Sold listings stay public with a sold banner and **no** buy/offer/contact CTAs.
  - **Store page** tabs are `?tab=listings|about|reviews` (`StoresController::TABS`),
    reviews paginated at 10 with `pagy(...)`.
  - **Sample data is dev-only**: `db/seeds/sample_*.rb` early-return unless
    `Rails.env.development?` (4 sample stores, 41 listings, 80 generated photos, 13
    reviews). Tests use fixtures only — fixture slugs deliberately avoid seed slugs.
  - **Gotcha — search vectors and fixtures**: `trg_listings_tsv` only fires on
    `UPDATE OF title, description`, so bulk fixture INSERTs leave `tsv` null. The global
    `setup` in `test/test_helper.rb` calls `Listing.reindex_search_vectors!`; keep it
    there rather than per test file.
  - **Gotcha — public pages and sessions**: `Authentication` now always runs
    `before_action :resume_session` and only then `require_authentication`; without that,
    public controllers (`allow_unauthenticated_access`) left `Current.user` nil, which
    broke cached-per-user fragments.
- **Seller listings (Phase 3a)** — authenticated, seller-scoped:
  - Routes: `namespace :sell` inside the locale scope — `resources :listings`
    + singular POST-only `resource :submission`/`:archival`/`:sale_mark` and
    `resources :category_fields, only: :show` (path param is the **category
    slug**; helper is singular `sell_category_field_path`).
    `Sell::BaseController` requires auth and bounces banned users to root.
  - **Scoping**: every lookup is `current_user.listings.friendly.find` →
    foreign listings 404. Index tabs `all|draft|pending_review|approved|
    rejected|sold|archived`, counts from ONE `group(:status)` query
    (`Listing.status_counts`), pagy via `results_pagination`.
  - **Material vs price edits** (`Listings::Update`): title/description/
    photos/specs/category changes on an APPROVED listing send it back to
    `pending_review` (`request_revalidation!`, no :submission gate);
    price/shipping/location/tag edits keep it live.
  - **Validation contexts**: required spec attributes error only on
    `:submission` (`valid?(:submission)` via `submit_for_review!`); unknown
    spec keys/values are rejected in every context. `Listing#archive!` and
    `#destroyable?` (draft/rejected/archived only, else 422).
  - **Stores**: `Stores::EnsureFor` creates the seller's individual store
    (name = username) on their first listing.
  - **Admin notification**: `Listings::Submit` inserts one
    `Notification(kind: "listing_submitted")` row per admin via
    `insert_all`, in the same transaction as the status change.
  - **Form**: one page + Stimulus `listing_form_controller.js`; two submit
    buttons carry `name="intent" value="submit|draft"`. Photos:
    multi + drag-drop, model validates max 12 / 10 MB / jpeg-png-webp;
    server re-render skips non-persisted or non-image attachments
    (`photo_variant_tag` cannot transform them). Price fields post EURO
    strings as `listing[price]` etc. — `Listings::FormAttributes.euros_to_cents`
    converts ("1.299,99" works); fields are `raw.key?`-guarded for PATCH.
- **Seller dashboard & store settings (Phase 3b)** — authenticated, seller-scoped:
  - Routes: `resource :dashboard` (also `sell_root`), `resource :store, only:
    %i[edit update]`, `resource :vacation, only: %i[create destroy]`,
    `resources :sales, only: %i[index show]`. `Sell::BaseController` renders
    `layout "sell"` (`layouts/sell.html.erb`, noindex) with the
    `sell/_sidebar` partial (store card + nav; horizontal scroll on mobile,
    vertical rail from `lg`). Header dropdown has "My store" links.
  - **Dashboard numbers live in `Sell::DashboardStats`** (one aggregate
    query per metric): live/in-review listings and `SUM(views_count)` are
    current/lifetime; favorites, sales and revenue are windowed to 30 days;
    revenue = `SUM(total_cents − commission_cents)` completed only
    (`Order#net_revenue_cents`); conversion = 30d sales / lifetime views,
    zero-guarded. Chart: ONE `date_trunc('week', created_at)` GROUP BY,
    zero-filled to 12 ISO weeks oldest-first, rendered as pure CSS bars
    (heights = `count / Result#weekly_max`). Stats fragment cached 5 min
    per store (`cache …expires_in: 5.minutes`).
  - **Needs attention**: `Listing.recently_rejected_for` (with
    `rejection_reason`), `Offer.pending_for_seller` (active + not_expired),
    `Conversation.unanswered_for_seller` (NOT EXISTS message from the
    seller).
  - **Store settings** go through `Stores::UpdateSettings` (euro strings
    `store[default_shipping]`/`store[free_shipping_threshold]` → cents;
    blank default → 0, blank threshold → NULL; uploads only reassigned when
    the form sent one). `Store` validations: name 2..60 unique, description
    ≤2000, `store_type` enum individual:0/business:1 — business requires
    `vat_number`, validated by `SpanishTaxIdValidator` (NIF
    `TRWAGMYFPDXBNJZSQVHLCKE` mod-23, NIE X→0/Y→1/Z→2, CIF control
    `(10 − Σ) mod 10` with `JABCDEFGHI` letters for K/P/Q/S/W, either for
    C/D/F/G…; class API `SpanishTaxIdValidator.valid?`), region ∈
    EsProvince, logo jpeg/png/webp ≤5 MB, banner ≤8 MB. Variants:
    `Store::LOGO_VARIANTS` thumb 256² fill / card 400² limit,
    `BANNER_VARIANTS` display 1600×400.
  - **Slug history**: `friendly_id :name, use: [:slugged, :history]` +
    `should_generate_new_friendly_id? = name_changed?`; public
    `StoresController#show` finds by old slug and 301-redirects
    (`redirect_to …, status: :moved_permanently`). Migration
    `20261117200002` creates the standard FriendlyId `friendly_id_slugs`
    table. GOTCHA: history rows come from `after_save :create_slug`, so
    FIXTURE stores have none — tests exercising old-slug resolution seed
    `store.slugs.create!(slug:)` or create via the model.
  - **Vacation mode**: `Store#enable_vacation!`/`#disable_vacation!`
    (boolean `vacation_mode`, no separate model). Listings remain publicly
    searchable (ListingSearch unchanged); `listings/show` renders a notice
    and disables buy/offer, `stores/show` a banner; toggling is POST/DELETE
    `/sell/vacation` from the sidebar.
  - **View gotcha**: lazy attachment assignment (`store.logo = file`) is
    deferred until save, so a 422 re-render has an unpersisted attachment
    with no `signed_id` — `store_logo_url`/`store_banner_url` require
    `attached? && persisted?`; also `store&.logo.attached?` only guards
    `logo` — chain `&.attached?` too.
- **i18n**: the 6 locale files currently share an identical tree of **759 keys**. Plurals
  must be nested (`count: { one:, other: }`) — i18n 1.15.2 does not resolve flat
  `*_one`/`*_other` keys. Locale files are machine-merged (`YAML.dump` → alphabetical
  keys); regenerate rather than hand-splicing.
- **Chat & offers (Phase 4a)**:
  - **Security discipline**: every conversation/offer read goes through the model
    scopes (`Conversation.for_user`, `Offer.for_seller`, `Offer.sent_by`,
    `current_user.blocks_cast`) — outsiders get 404s, never 403s.
  - **Writes go through services only**: `Conversations::Start`, `Messages::Send`,
    `Offers::{Create,Accept,Decline,Withdraw}`; controllers stay skinny.
    Offer rules: amount `<` asking price, `≥ Offers::Create.minimum_for`
    (`ceil(price_cents × Setting["min_offer_percent"] / 100)`, default 50),
    one pending offer per buyer (new ones withdraw the old), 48h
    `expires_at`, accept → listing `reserved` (`reserved_for_id`,
    `reserved_until = now + 48h`) + every other pending offer auto-declined;
    `ExpireOffersJob` (recurring every 15 min) expires pending offers and
    releases lapsed reservations.
  - **Real-time**: `Message#broadcast_creation` (after_create_commit) appends the
    bubble to the `conversation` stream and REPLACES the inbox row
    (`target: dom_id(conversation)`) on each participant's `[user, :inbox]`
    stream; views subscribe via `turbo_stream_from`. `_row.html.erb` takes a
    `viewer:` local (broadcasts pass it explicitly). Bubble alignment and
    recoloring are client-side (`thread_controller.js` reads
    `data-message`/`data-sender-id`/`data-bubble` + `data-thread-current-user`
    and re-aligns mutations via MutationObserver) because the broadcast partial
    has no `current_user`. turbo-rails **2.x signs stream names** (GID-based);
    never assume plain `conversation_123` stream names.
  - **Notification e-mail throttle**: `Messages::Send` always creates the
    `new_message` Notification, but only enqueues `MessageNotificationMailer`
    when the recipient has no *unread* notification of that kind for that
    conversation in the last 15 min (`Notification.recent_unread_message_for?`).
  - **Rate limits**: `MessagesController` uses its own
    `ActiveSupport::Cache::MemoryStore` constant (`RATE_LIMIT_STORE`) with
    `rate_limit to: 30, within: 1.minute, by: -> { Current.user.id }` → 429;
    tests clear that store in setup. Message body max 2000 chars; the
    contact-detail/off-platform-payment regex banner is advisory only.
  - **Read receipts**: GET `conversations#show` marks the thread read;
    POST `read_receipt` (turbo) re-renders the header badge partial
    (`Conversation.unread_badge_count_for`, cached per user).
  - **Currency in tests**: services/controllers format with
    `Money#formatted` — under `:en` that's `€300.00` (unit prefix), under
    `:es` `300,00 €`. Tests run `:en`.



## Code map


| Area | Files |
| --- | --- |
| Routes (locale-scoped) | `config/routes.rb` — root `pages#home`, `resources :listings, only: %i[index show]` (nests `resources :offers, only: %i[new create]`), `resources :categories, only: :show, path: "c"`, `resources :stores, only: :show`, `get "search" → listings#index`, `namespace :sell { root "dashboards#show"; resources :listings + resource :submission/:archival/:sale_mark + resources :category_fields, only: :show; resource :dashboard; resource :store, only: %i[edit update]; resource :vacation, only: %i[create destroy]; resources :sales, only: %i[index show] }`, `resource :session`, `resources :passwords`, `resource :registration`, `resources :conversations, only: %i[index show create]` (nested `resources :messages, only: :create` + `resource :read_receipt, only: :create`), `resources :blocks, only: %i[index create destroy]`, `resources :offers, only: :index` + `resource :acceptance/:decline/:withdrawal` nested under offers; 4b: `resource :cart` + `resources :cart_items, only: %i[create update destroy]`, `resource :checkout, only: %i[show create]`, `resources :addresses`, `resources :orders, only: %i[index show]` (nested `resource :completion/:cancellation/:dispute` + `resources :delivery_confirmations, only: :create`), `namespace :sell { resources :sales { resource :payment_confirmation; resource :shipment; resource :cancellation } }`, `resource :stripe_webhook, only: :create`, `resources :reviews, only: %i[new create]` |
| Auth | `app/controllers/concerns/authentication.rb` (cookie resume, `Current.session`), `sessions_controller.rb`, `passwords_controller.rb`, `passwords_mailer.rb` |
| Sign-up | `registrations_controller.rb` + `views/registrations/new` |
| User model | `app/models/user.rb` — `email_address` (normalized downcase, uniq index), `username` (uniq index, `/\A[a-zA-Z0-9_\-]{3,30}\z/`), `first_name`, `last_name`, `phone`, `role` enum (user:0 admin:1), `locale` (default "es"), `country_code` (default "ES"), `confirmed_at`, `banned_at` (`banned?/ban!/unban!`), `display_name`; has_many: store, listings, sales/orders, favorites, follows, seller_follows, saved_searches, conversations, offers, carts, reviews, sent_messages, api_tokens |
| Locale switching | `application_controller.rb`, `config/application.rb`, `config/locales/*.yml`, `script/lint_locale_keys.rb` |
| Layout & chrome | `app/views/layouts/application.html.erb`, `_header.html.erb` (announcement, logo, search `GET /:locale?q=`, wishlist/notifications/cart icons, account dropdown, desktop mega menu + mobile slide-in menu, both cached per locale and busted by `Category.maximum(:updated_at)`), `_footer.html.erb` (newsletter, link columns, language switcher, copyright), `_flashes.html.erb` |
| Design tokens | `app/assets/tailwind/application.css` (`--color-primary` #4f46e5, `--color-accent` #f97316, surface/surface-muted/text/muted/border; `.dark` overrides; component classes `btn-primary/secondary/ghost`, `card`, `chip`, `chip-choice`, `input`, `select`, `nav-link`, `icon-button`, `series-nav`, `filters-sheet`, `scroll-snap-row`) |
| Stimulus | `app/javascript/controllers/{theme,menu,mega_menu,filters,gallery,listing_form}_controller.js` — `mega-menu` hover/focus panels (Esc + focusout close), `filters` mobile `<dialog>` sheet + auto-submit, `gallery` swipe/keyboard carousel, `listing_form` category-picker Turbo-Frame reload + title counter + photo drag-drop previews/client-side limits + tag limit |
| Sell area (3a) | `app/controllers/sell/{base,listings,category_fields,submissions,archivals,sale_marks}_controller.rb`, `app/services/listings/{form_attributes,create,update,submit}.rb`, `app/services/stores/ensure_for.rb`, `app/models/es_province.rb` (+ `config/data/es_provinces.yml`), `app/views/sell/listings/{index,new,edit,_form}.html.erb`, `app/views/sell/category_fields/{show,_picker,_spec_fields}.html.erb`, `app/views/shared/_error_summary.html.erb` (local: `resource:`), `app/helpers/sell/listings_helper.rb` (status badges) |
| Sell dashboard & settings (3b) | `app/controllers/sell/{dashboards,stores,vacations,sales}_controller.rb` (base uses `layout "sell"`), `app/services/sell/dashboard_stats.rb` (`Result` struct, aggregate-only queries, 12-week zero-filled chart), `app/services/stores/update_settings.rb`, `app/validators/spanish_tax_id_validator.rb`, `app/views/layouts/sell.html.erb`, `app/views/sell/{_sidebar}.html.erb`, `app/views/sell/dashboards/show.html.erb` (KPIs, CSS bar chart, needs-attention, top 5, cached fragment), `app/views/sell/stores/edit.html.erb`, `app/views/sell/sales/{index,show}.html.erb`, `app/helpers/store_helper.rb` (`store_logo_url`/`store_banner_url`/`store_initials`), `app/helpers/sell/{sales,sidebar}_helper.rb`; migrations `20261117200001`–`200003` (store settings columns, friendly_id_slugs, stores.city/region) |
| Browse & search (2b) | `app/services/listing_search.rb` (`Result` struct, one facet-count query, `with_card_includes`), `app/controllers/{listings,categories,stores}_controller.rb` (skinny; `search_params` + `current_country_code` in `ApplicationController`), `app/helpers/listings_helper.rb` (`money`, `spec_value_label`, `stars`, `applied_filter_chips`, `facet_options*`, `listing_photo_tag`, `photo_variant_tag`, breadcrumbs, `url_without_filter`), `app/jobs/listing_view_job.rb` (view counter) |
| Browse UI (2b) | `app/views/listings/{index,_browse,_filters,_results,show,_show_specs,_show_shipping}.html.erb` (also rendered by `CategoriesController#show` — no separate category template — and by `StoresController#show`), `app/views/shared/{_listing_card,_card_rail}.html.erb`, `app/views/stores/show.html.erb` (tabs `?tab=listings|about|reviews`), `app/views/pages/home.html.erb` + `app/views/pages/home/{hero,categories,deals,newest,gpus,saved,sold,trust,newsletter}.html.erb` |
| Taxonomy | `category.rb` (self-referential `parent_id`, JSONB `names` locale maps, recursive CTEs `self_and_descendant_ids`/`self_and_ancestor_ids`, FriendlyId; NOTE `categories.listings_count` is a plain counter_cache of ALL listings including drafts/rejected — public per-category counts must query `Listing.published`/`visible`), `spec_attribute.rb` (`key`, JSONB names, `input_type` enum with `prefix: true`) + `spec_option.rb` + join `category_spec_attribute.rb` — spec attributes attach to any category and are inherited down the tree (`Category#all_spec_attributes`) |
| Listings | `listing.rb` — FriendlyId `:slugged, :sequentially_slugged` (`slug_candidates`), pg_search `search_text` (tsvector column `tsv` + trigger + GIN in migrations 090008/090009), enums `condition` (brand_new/open_box/used_like_new/used_good/for_parts) and `status` (draft/pending_review/approved/rejected/sold/archived/reserved) with transitions `submit_for_review!`/`approve!(admin)`/`reject!(reason, admin:)`/`mark_sold!`/`reserve_for!(buyer)`/`release_reservation!` raising `Listing::InvalidTransition`; `RESERVATION_TTL` 48h + `reserved_for_id`/`reserved_until` (reserved stays public with a banner); integer-cent columns (`price_cents` etc.) + `Money` value object (`Listing#price`, `discount_percent`); JSONB `specs` (may be empty — accessories/games have none — but must be a Hash); photos via ActiveStorage (`has_many_attached`, 12/10 MB/jpeg-png-webp model validations); scopes: `published/visible/featured/in_country/recent`; labels/tags: `label.rb`, `listing_label.rb`, `seller_tag.rb`, `listing_tag.rb`, moderation: `moderation_event.rb` |
| Stores & reputation | `store.rb` (FriendlyId `:slugged, :history` + `should_generate_new_friendly_id?` on rename → 301 old URLs from the public `StoresController`, `store_type` enum, counters `listings_count/reviews_count/rating_average`, `refresh_rating!`, `enable_vacation!`/`disable_vacation!`, logo/banner uploads with `LOGO_VARIANTS`/`BANNER_VARIANTS` + size/type validations, Spanish VAT rule for business stores), `review.rb` (uniq `order_id`, reviewer/store/seller), `favorite.rb` (counter cache on `favorites_count`), `follow.rb` |
| Commerce | `cart.rb` (`for_user`/`for_token`/`token`, `cart_items` association — NOT `items` — `subtotal_cents` — no `total_cents`), `cart_item.rb` (NO approval validation here: rules live in `Carts::AddItem`/`Checkout::PlaceOrders`/`Carts::Summary`), `order.rb` (number `PCM-YYYY-NNNNNN` from `order_number_seq`, integer-cent totals + `recalculate_total`, `net_revenue_cents` = total − commission, `apply_commission!` gated by Flipper `:commissions` + `Setting commission_percent`; 4b state machine: `status` enum `pending_payment/paid/shipped/delivered/completed/cancelled/refunded/disputed` + transitions `pay!/ship!(carrier:, tracking_number:)/mark_delivered!/complete!/cancel!/open_dispute!` raising `Order::InvalidTransition`, timestamp columns `paid_at/shipped_at/completed_at/cancelled_at` + `checkout_token` (idempotency replay key), `BUYER_PROTECTION_WINDOW` 2d sets `buyer_protection_until` on delivery, `AUTO_CANCEL_AFTER` 72h, scopes `awaiting_auto_completion/auto_cancellable`, `restore_listings!` returns units to sellers on cancel), `order_item.rb`, `address.rb`, `offer.rb` (`OFFER_TTL` 48h, `for_seller`/`sent_by`/`active`/`not_expired` scopes, `accept!`/`decline!`/`withdraw!` false when stale, `expire!`), `app/services/commission_calculator.rb`, offers services `app/services/offers/{create,accept,decline,withdraw}.rb` (accept reserves the listing + auto-declines the others), `app/jobs/expire_offers_job.rb` (recurring `expire_offers` every 15 min in `config/recurring.yml`) |
| Messaging | `conversation.rb` (`for_user` scope — the only controller lookup; `unanswered_for_seller` (NOT EXISTS seller message), `other_party`, `blocked_by?`, `unread_count_for`, `unread_badge_count_for` (cached per user), `unread_counts_by_conversation_for` (batched), `mark_messages_read_for`, `clear_unread_cache`), `message.rb` (`MAX_BODY_LENGTH` 2000, kind enum text/offer/system, `SAFETY_PATTERNS` + `safety_flagged?` (advisory only), `unread_by`, `after_create :touch_conversation`, `after_create_commit :broadcast_creation` — Turbo append to thread + replace inbox rows), `block.rb` (`:cannot_block_self` + blocker/blocked uniqueness → `:taken`); services `app/services/conversations/start.rb`, `app/services/messages/send.rb` (guards + Notification + throttled e-mail) |
| Chat & offers UI (4a) | `app/controllers/{conversations,messages,read_receipts,blocks,offers,acceptances,declines,withdrawals}_controller.rb`, `app/views/conversations/{index,show,_row,_tabs,_composer}.html.erb` (show = inbox rail + thread, `turbo_stream_from` tags), `app/views/messages/{_message,_offer_card}.html.erb` (neutral, client-aligned), `app/views/offers/{new,index,_row}.html.erb`, `app/views/blocks/index.html.erb`, `app/views/shared/_unread_conversations_badge.html.erb` (header), `app/helpers/conversations_helper.rb` (`user_initials`), `app/javascript/controllers/{thread,composer}_controller.js`; mailer `message_notification_mailer.rb` + `views/message_notification_mailer/{new_message.html,text}.erb` (recipient locale) |
| Cart & checkout (4b) | `app/controllers/{carts,cart_items,checkouts,addresses}_controller.rb` — guest cart = `Cart.token` in a signed permanent cookie (`:cart_token`), user cart = `Cart.for_user`; `CheckoutsController#show` mints `session[:checkout_token]`, `#create` checks the **replay branch BEFORE the empty-cart guard** (first submit empties the cart, so a double click must replay, not bounce) then `Checkout::PlaceOrders`; `Carts::Merge` is called from `authentication.rb#start_new_session_for` (login folds the guest cart in, drops non-purchasable items, destroys the guest cart, clears the cookie). Services `app/services/carts/{add_item,merge,summary}.rb` (AddItem = the ONLY add-path purchase-rule enforcer: approved + not own listing + not reserved + seller not on vacation + quantity ≤ stock; Summary = groups by seller, marks `stale` items, per-seller shipping = 0 when pickup allowed and chosen, 0 over `Store#free_shipping_threshold_cents`, else max of item `listing.shipping_price_cents`), `app/services/checkout/{place_orders,direct_payment}.rb` (PlaceOrders: one order per seller, locks listings with `SELECT ... FOR UPDATE` + re-validates inside the transaction — a listing sold mid-checkout fails the whole call with `:not_purchasable`, applies commission when `:commissions` is on, sets `checkout_token`, empties the cart, notifies + e-mails both parties; `Result#success?`), `app/services/payments/{stripe_checkout,handle_webhook}.rb` (Stripe only when `Flipper :stripe_checkout` AND `ENV["STRIPE_SECRET_KEY"]`; webhook verifies `Stripe::SignatureVerifier` against `STRIPE_WEBHOOK_SECRET`, marks linked orders paid — order ids come from `stripe_session["metadata"]["order_ids"]`, stripe-ruby 21 StripeObject has NO `dig`). Views `app/views/carts/show.html.erb` (stale items greyed, per-seller shipping rows), `app/views/checkouts/show.html.erb` (address picker + per-seller pickup checkboxes + hidden `checkout_token`), `app/views/addresses/{index,new,_form}.html.erb` |
| Order lifecycle (4b) | buyer transitions under `resources :orders` (`orders/{delivery_confirmations,completions,cancellations,disputes}_controller.rb`, scoped to `current_user.orders` → outsiders/buyers-vs-sellers all 404), seller fulfilment nested under `sell/sales/:sale_id/*` (`sell/{sales,payment_confirmations,shipments,cancellations}_controller.rb`, scoped to `current_user.sales` — the buyer 404s on seller routes and vice versa); `app/services/orders/transition.rb` wraps the model transition + Notification + mailer; `app/jobs/auto_complete_orders_job.rb` (recurring `auto_complete_orders` in `config/recurring.yml`: completes `delivered` past `buyer_protection_until`, auto-cancels `pending_payment` older than `Order::AUTO_CANCEL_AFTER`); `app/mailers/order_mailer.rb` (`new_sale`/`confirmation`/`payment_received`/`order_shipped`, recipient locale; `ApplicationMailer` now `helper ListingsHelper` for `money()`); views `app/views/orders/{index,show,_timeline}.html.erb`, `app/views/sell/sales/{index,show}.html.erb` (fulfilment actions), `app/views/reviews/{new,create}` (one review per completed order, `Review` uniq `order_id`); listings sold via checkout use `Listing#mark_sold!`, cancellation restores with `reinstate!`/`add_back_quantity!` |
| 4a review fixes | `Offers::Accept` now locks offer+listing+all sibling offers and re-checks staleness INSIDE the transaction (second concurrent accept → `:stale`); `MessagesController` rate-limits via `rate_limit to: 30, within: 1.minute, by: -> { Current.user.id }` on the default `Rails.cache` (test env `config.cache_store` switched `:null_store` → `:memory_store` so this is testable) |
| Platform | `country.rb` (JSONB-free locale rows via `name_key` i18n keys, `Country.seed_defaults!` ES-only), `setting.rb` (`get/set` + Rails.cache key `settings/<key>`, `seed_defaults!`), `api_token.rb` (`issue_for` → SHA-256 `token_digest`, `authenticate` active-only), `legal_page.rb`, `newsletter_subscription.rb`, `notification.rb`, `saved_search.rb`, `money.rb` (value object: `cents`/`amount`/`to_s`) |
| Seeds (Phase 2a) | `db/seeds.rb` (loads `db/seeds/support/seed_loader.rb` + one loader per concern, idempotent upserts), raw data `db/seeds/data/{categories,spec_attributes,category_spec_attributes,labels,seller_tags}.yml` — counts: 61 categories, 34 spec attributes, 293 options, 88 category attachments, 13 labels, 21 seller tags, 6 countries, 5 settings (4 core + `min_offer_percent` since Phase 4a) |
| Seeds (Phase 2b, dev-only) | `db/seeds/sample_listings.rb` early-returns unless `Rails.env.development?`; seeds 5 sample sellers (store + user each), 41 listings across the taxonomy (labels, seller tags, JSONB specs, favorites/views counters, `status: sold` on a few indexes, `featured_until = 7.days.from_now` on the featured ones), 13 reviews through delivered orders, then attaches 80 generated 1200×900 placeholder photos (ImageMagick gradients cached in `tmp/sample_photos/` — no fonts on this box, so no text overlay). Idempotent: re-running creates 0 records. Dev DB after seeding: 42 listings (39 approved, 3 sold), 80 attachments, 13 reviews, 5 sample stores |
| Migrations | Phase 0: `20261116205301…205400`. Phase 1 domain: `db/migrate/20261117090001`–`20261117090033` (countries, settings, stores, categories, spec_*, listings + tsv trigger/GIN, labels/tags/moderation, favorites/follows, saved_searches, conversations/messages/blocks, offers, carts/cart_items, addresses/orders/order_items, reviews, notifications, newsletter, legal_pages, api_tokens, user ban fields, active_storage). Phase 3b: `20261117200001` (stores: returns/shipping policies, shipping-default cents), `20261117200002` (friendly_id_slugs), `20261117200003` (stores.city/region). Phase 4a: `20261117210001` (messages: `kind` enum + `offer_id` FK), `20261117210002` (listings: `reserved_for_id` FK + `reserved_until`). Phase 4b: `20261117223000` (orders: `paid_at/completed_at/cancelled_at` datetimes + `checkout_token` string + indexes on `checkout_token`/`status`; `shipped_at`/`delivered_at` already existed since Phase 1). Schema dump: `db/structure.sql` (schema_format: sql in `config/database.yml`) |
| Tests | `test/models/user_test.rb`, `test/models/{listing,category,setting,country,api_token,review,favorite}_test.rb`, `test/models/store_test.rb` (3b: name/description/VAT/business/region/logo/banner validations, slug history — create via model, not fixtures), `test/validators/spanish_tax_id_validator_test.rb` (NIF/NIE/CIF vectors incl. G02377372, P0200000H), `test/services/{commission_calculator,listing_search,sell/dashboard_stats}_test.rb` (dashboard: windowed revenue nets commission, zero-filled ISO weeks, unanswered/pending scopes; fixture order `one` is a completed in-window order for seller two and orders' `created_at` defaults to now), `test/controllers/{pages,listings,categories,stores,sessions,passwords}_controller_test.rb`, `test/integration/sell_listings_test.rb` (3a + photo purge-after-commit regression: failed update keeps photos attached), `test/integration/sell_dashboard_test.rb` (auth, KPI render, attention), `test/integration/sell_store_settings_test.rb` (euro fields, business VAT, oversized logo 422, rename → 301 via seeded `slugs` row), `test/integration/sell_vacation_test.rb` (toggle, listing notice/disabled buy, store banner), `test/helpers/listings_helper_test.rb`, `test/test_helpers/session_test_helper.rb` (`sign_in_as`); fixtures for users (incl. `banned`)/countries/categories/spec_*/labels/seller_tags/stores/listings/orders/order_items/files. `test_helper.rb`: `I18n.default_locale = :en`, `routes.default_url_options[:locale] = :en`, and a **global** `setup { Listing.reindex_search_vectors! }` (fixture INSERTs do not fire `trg_listings_tsv`, which only fires on UPDATE of title/description). GOTCHA: fixture orders use `number:` `PCM-2025-000001/2` (deliberately NOT `PCM-2026-*`: fresh `order_number_seq` nextvals are 1,2 and would collide with same-year fixture numbers when tests create orders); create extra orders in tests with an explicit unique `number:` or let `assign_number` pick from the sequence. `listings_controller_test.rb` also guards against N+1 by counting `sql.active_record` notifications. Phase 4a: `test/models/{conversation,message,offer}_test.rb`, `test/services/{conversations/start,messages/send}_test.rb`, `test/services/offers/{create,decisions}_test.rb`, `test/jobs/expire_offers_job_test.rb`, `test/mailers/message_notification_mailer_test.rb` (mailer renders in the RECIPIENT's locale — fixture user `one` is `es`), `test/integration/messaging_test.rb` (scoping, start refusals, read receipts, blocks incl. `cannot_block_self`/`taken`, 30/min → 429 via `MessagesController::RATE_LIMIT_STORE.clear` in setup), `test/integration/offers_test.rb` (form hints in `:en` money format `€300.00`, decision flows, reserved 422 + banner, tab scoping), `test/integration/turbo_broadcasts_test.rb` (`capture_turbo_stream_broadcasts` returns Nokogiri elements — assert `el["action"]`/`el["target"]`/`to_html`; commit callbacks DO fire in transactional tests on this Rails). Phase 4b: `test/models/{cart,order}_test.rb`, `test/services/{carts_add_item,carts_merge,carts_summary,checkout_place_orders,checkout_direct_payment,payments_stripe_checkout}_test.rb` (PlaceOrders covers per-seller split + recomputed totals, commission flag off/on, free-shipping threshold, pickup, the concurrency guard — a `Listing.singleton_class.define_method(:find)` swap sells the listing mid-transaction → `:not_purchasable` + zero orders — and token replay), `test/jobs/auto_complete_orders_job_test.rb`, `test/controllers/{carts,checkouts,orders,stripe_webhooks}_controller_test.rb` + `test/controllers/sell/sales_controller_test.rb` (role guards: buyer hitting seller routes 404, outsider 404, seller can't confirm delivery). Fixtures add `carts.yml`, `cart_items.yml`, `addresses.yml` (address columns: `full_name/line1/line2/city/region/postal_code/country_code/phone/default`). **Minitest 6 has no `minitest/mock`** — no `stub`; swap class methods via `Klass.singleton_class.define_method(...)` + `remove_method` in `ensure` (see Stripe stubs). Integration tests can't read signed cookies — guest carts via `Cart.where(user: nil).order(:id).last`, assert `cookies[:cart_token].blank?` after login. `perform_enqueued_jobs` needs `include ActiveJob::TestHelper`. Test env uses `config.cache_store = :memory_store` (message rate limiter needs a real store) |

## Open items (next phases)

- Seller follow-ups: favourites/wishlist persistence, per-listing edit of
  labels. (Listing create/edit, publish flow, photo upload, mark-sold and
  archiving shipped in Phase 3a; store settings, dashboard, vacation mode
  and a read-only sales list shipped in Phase 3b — fulfilment actions and
  payments shipped with Phase 4b checkout; payout UI still open.)
- Cart + checkout + order lifecycle shipped in Phase 4b (guest carts + login
  merge, per-seller orders, direct payment + Stripe behind flag `stripe_checkout`,
  full state machine with role-guarded transitions, auto-complete/auto-cancel job,
  reviews on completed orders). Follow-ups: payout/wallet UI, refund flows
  (`refunded` state exists but no admin refund action yet), dispute handling UI
  beyond opening, real Stripe keys/webhook endpoint wiring in production.
- "Sell to us" (flag `sell_to_us`).
- Google login (flag `google_login`), email confirmation (`confirmed_at` exists but is unused).
- `/api/v1` namespace (`ApiToken.authenticate` ready), sitemap_generator config, meta-tags per-page SEO.
- Seed data: reference data done (Phase 2a) and dev demo catalogue done (Phase 2b,
  dev-only). Photo placeholders are generated gradients — replace with real assets if
  screenshots/design reviews matter. pg_search typo tolerance (dmetaphone) if needed.
- Saved searches and reviews UI (models exist; Phase 2b shows
  read-only reviews on the store page). Chat/offers UI shipped in Phase 4a —
  follow-ups there: message edit/delete, typing indicators, photo-in-chat,
  notification inbox page (the `Notification` records exist and e-mails go
  out; only the unread badge is surfaced in the header).
- Add `script/lint_locale_keys.rb` to CI.
