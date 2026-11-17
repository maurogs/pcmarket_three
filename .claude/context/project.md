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
accept-to-reserve, all I18n'd), Phase 4b cart/checkout/orders, and Phase 5
**engagement & account** — wishlist/favorites with price-drop alerts, store
follows, saved searches with new-matching-listing alerts + hourly digest, a
notification centre with unread badge, and the `/account` area (profile,
security, notification preferences, GDPR export & deletion). Phase 6 shipped
the full **admin panel** — part 1 (`/admin`: moderation queue + bulk actions,
listing admin edits/unpublish/delete/CSV, user roles/bans/impersonation,
store verify/hide, dashboard, append-only audit log) and part 2 (order
management + dispute refunds, review moderation, category/spec taxonomy,
country launch toggles + legal-page gate, feature-flag console, site
settings + maintenance mode, legal pages, newsletter list, audit-log
browse), and Phase 7a **PC Finder, performance scoring & sell-to-us** — a
`/pc-finder` gaming-PC quiz backed by a computed 0–1000
`performance_score` on listings, and a trade-in quote flow behind the
`sell_to_us` flag with an admin fulfilment walk, and Phase 7b **trust,
content & compliance** — the Trust & Safety page, six static content pages,
a public contact form + admin inbox, listing reports with an admin
resolution inbox, public legal-page delivery with a locale fallback chain,
GDPR cookie consent and a rebuilt footer. Phase 8a added SEO (meta tags,
JSON-LD, dynamic robots.txt, sitemaps, localized error pages) and Phase 8b
the **JSON API v1** — a bearer-token REST surface at `/api/v1` mirroring the
whole web app (catalog, engagement, chat/offers, cart/checkout/orders, sell
area) with OpenAPI 3.1 docs at `/api/v1/docs`, direct uploads, bearer-authed
Action Cable and a push-device registry. Phase 8c is **performance**: Prosopite
N+1 scanning in tests (step B), warm-path query fixes, anonymous HTTP caching
(`public, max-age=60, stale-while-revalidate=300`), responsive card images
(400/800w webp srcset), and production perf config — YJIT, WEB_CONCURRENCY
(step C), measured by `script/perf_baseline.rb` (see `tmp/perf/` before/after
tables).

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
- **API**: shipped at `/api/v1` in Phase 8b — see the "JSON API v1 (Phase 8b)"
  decision block below the SEO (8a) block.
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
  - **Demo data is dev-only** (Phase 9): `db/seeds/demo.rb` (`DemoSeed`)
    refuses production unless `ALLOW_DEMO_SEED=1`; in dev it seeds 300
    listings (SEED_LISTINGS), 101 users, real photos via
    `app/services/demo_images/` — see the Seeds (Phase 9) code-map row.
    Tests use fixtures only — fixture slugs deliberately avoid seed slugs.
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
- **i18n**: the 6 locale files currently share an identical tree of **2656 keys**. Plurals
  must be nested (`count: { one:, other: }`) — i18n 1.15.2 does not resolve flat
  `*_one`/`*_other` keys. **Enum labels** are FLATTENED slash keys under
  `attributes.<model>` (`"status/draft": Draft` + plain `status: Status`) because
  call sites use `Model.human_attribute_name("status/draft")`; a nested hash there
  never resolves and crashes plain attribute lookups ("can not be used with
  :count => 1"). Locale files are machine-merged (`YAML.dump` → alphabetical
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
- **Engagement & account (Phase 5)** — authenticated; account area uses
  `Account::BaseController` (`require_authentication`, `layout "account"`
  with `layouts/_account_nav`):
  - **Favorites**: `FavoritesController` (`GET /favorites` wishlist +
    create/destroy, Turbo Stream swaps `shared/_favorite_button` in place;
    create looks up `Listing.visible.find(params[:listing_id])`, destroy by
    favorite id via `current_user.favorites`). `Favorite#price_cents_at_save`
    records the price when saved → `#price_dropped?` powers the wishlist's
    "price dropped since you saved it" badge.
  - **Price-drop alerts**: Listing `after_update_commit :alert_price_drop`
    (when `saved_change_to_price_cents?`) runs `Listings::PriceDropNotifier`
    **synchronously** — only on a price CUT and only while `approved?`.
    Service: **24h per-listing cooldown** (`recently_notified?` re-queries the
    `price_drop` Notification rows via `payload->>'listing_id'`), notifies
    only favorites whose `price_cents_at_save` is above the new price;
    Notification always created, `PriceDropMailer` only when
    `user.wants_email?("price_drop")`.
  - **Follows**: nested `resource :follow` under stores
    (`store_follow_path(store)` POST/DELETE), `FollowsController` looks up
    `Store.visible.friendly.find` (hidden/anonymised stores 404) and swaps
    `shared/_follow_button` over turbo_stream; model rejects self-follows.
  - **Saved searches**: filters stored as-is in JSONB `filters` (the same
    params the browse form posts: `q, category, min_price, max_price,
    condition[], f{}, labels[], tags[], seller`);
    `SavedSearch.new_from_search(user:, name:, search_filters:)` takes the
    **permitted Parameters** (max 25/user → base error). `email_alerts`
    defaults to **false at the attribute level** (DB column default true).
    Routes are `index/create/update/destroy` — update is PATCH and just
    toggles `email_alerts` (turbo_stream replaces the row partial).
  - **Matching pipeline**: Listing `after_commit on: :update` when status
    transitions **into approved** → `SavedSearchMatchJob(listing_id)` →
    `SavedSearches::MatchNewListing` (class, `self.call`). Matching is
    SQL prefilter (saved search's `category_id` ∈ listing's ancestor ids,
    Ruby price-band check) then the authoritative answer from
    **`ListingSearch.new(search_params, only_id: listing.id).match?`** — one
    code path, so keyword/spec/condition/label rules can never drift from
    the results page. Each match = one `saved_search_match` Notification
    (payload carries `saved_search_name` for the mail). Instant e-mail
    (`SavedSearchMailer#match_found`) goes at most once per user when a
    matching search has `email_alerts` AND `wants_email?("saved_search")`,
    then `touch(:last_notified_at)` on those searches as the watermark.
  - **Digest**: `SavedSearchDigestJob` runs from `config/recurring.yml`
    (`saved_search_digest`, hourly, production block) → `SavedSearchDigest`
    (plain class, `MAX_LISTINGS_PER_EMAIL` 10): one e-mail per user for
    matches their instant alerts skipped, via
    `Notification.unsent_saved_search_matches(search)` (created after
    `last_notified_at`), stamps `last_notified_at` after sending; opted-out
    users' matches stay pending until they opt back in.
  - **Notification centre**: `NotificationsController#index` (paginated,
    `Notification.recent`, clears the per-user unread-count cache) +
    `NotificationsReadsController` (POST `notifications_read` = mark ALL
    read; NOTE `resource :notifications_read` infers the PLURAL constant).
    Kind text/icon/link mapping lives in `NotificationsHelper`
    (`notification_text`/`notification_icon`/`notification_link`,
    payload-driven); header bell badge is
    `shared/_notifications_badge` (`Notification.unread_count_for`,
    live via `turbo_stream_from Current.user, :notifications`;
    cache-busted by `after_create_commit` + the read paths).
    `Notification::KINDS` lists the ten kinds the centre renders.
  - **E-mail preferences**: sparse JSONB `users.notification_preferences` —
    `EMAIL_PREFERENCE_KEYS` (`email_new_message`, `email_offers`,
    `email_orders`, `email_price_drop`, `email_saved_search`,
    `email_newsletter`), all default ON except the newsletter; missing keys
    fall back to defaults in `wants_email?`. The form posts all six keys
    (hidden blanks + checked values) and
    `User#update_notification_preferences` writes the full matrix.
    `data_export` e-mails are transactional — no preference gates them.
  - **GDPR**: `Users::Anonymize.call(user)` raises
    `Users::Anonymize::OpenOrderError` when open orders exist
    (`open_orders_count`, also shown on the confirm page), then anonymises
    the user row via `update_columns` and archives non-archived/non-sold
    listings (drafts too, `where.not(status: %w[archived sold])`).
    Export: `account/data_exports#create` → `Users::DataExportJob` builds
    `Users::DataExport` JSON, **attaches it to the user** (`user.export`
    ActiveStorage) and mails the signed link via `DataExportMailer#ready`
    (7 days).
  - **Password change**: `User#current_password` is a virtual
    `attr_accessor` — `Account::SecuritiesController#update` assigns it
    before `authenticate` so `shared/_error_summary` renders
    `current_password` errors on the 422 re-render.
  - **Rails 8.1 / test gotchas**: mailer methods return lazy
    `MessageDelivery`s — `NullMail` assertions need `…action.message`, and
    `…deliver_now` must be called on the delivery; multipart
    `mail.body.to_s` is EMPTY — assert on `text_part.body.decoded`; long
    URLs are quoted-printable soft-broken — match short fragments, not
    `href="…"`; plain `ActiveSupport::TestCase` does NOT clear
    `ActionMailer::Base.deliveries` — clear it in setup when counting
    absolute deliveries.
- **PC Finder, performance & sell-to-us (Phase 7a)**:
  - **Performance score**: 0–1000 `listings.performance_score` (column since
    Phase 1; partial index `20261118020002`). `Performance::Scorer.score_from_specs`
    reads the TEXT specs `gpu_model`/`cpu_model` against tier tables
    `config/data/{gpu,cpu}_tiers.yml` (names fuzzy-normalized: brand words +
    laptop/mobile suffixes dropped, punctuation stripped; 75% GPU + 25% CPU,
    re-normalized when only one resolves, **nil** when neither — never a fake
    score). Only `Listing::SCORABLE_CATEGORY_SLUGS` (gaming-pcs, workstations,
    laptops + descendants) score — `Listing#scorable_category?` is PUBLIC
    (the rake task calls it); `refresh_performance_score` before_save keeps
    new rows fresh; `bin/rails performance:backfill` covers old ones
    (deliberate `update_column`). `Performance::FpsEstimator` (score → FPS
    per game, tables in `config/data/games.yml` per resolution/FPS target)
    clamps inputs to `SCORE_CAP = 1000`: above the tier scale the
    per-resolution extrapolation slopes cross and invert.
  - **PC Finder**: `/pc-finder` quiz + `/pc-finder/results`, both
    `allow_unauthenticated_access`. `PcFinder::Search`: gaming-pcs subtree,
    budget bands (`under_700|700_1200|1200_2000|over_2000`, cents), seller
    tags AND-ed, score floor = MAX of selected games' `required_score` at
    resolution×fps; order = **value** (`performance_score / price`, unscored
    → 0 and sink), 9/page. GOTCHA — partial locale scopes must NOT start
    with `_`: lazy partial lookup for `pc_finder_results/_result.html.erb`
    searches `pc_finder_results.result.*` (the partial's leading underscore
    is stripped from the lookup) — the original `_result:`/`_page:` keys
    never resolved and were renamed in all 6 files.
  - **Trade-ins** behind Flipper `:sell_to_us` (public controllers
    `head :not_found` while off): `TradeIn` (migration `20261118020001`) —
    status enum `quoted/accepted/received/inspected/paid/rejected/expired`
    + `TRANSITIONS` map + `transition_to!`/`expire!` raising
    `TradeIn::InvalidTransition`; `QUOTE_TTL` 7d; pricing from
    `config/data/trade_in_prices.yml`. Anonymous quote
    (`TradeIns::Quote`, user_id nil) → login + accept
    (`TradeIns::Accept` via `TradeInAcceptancesController`, stale quotes
    refused) → admin walk in `Admin::TradeInsController` (audited
    `update`). GOTCHA — never define a custom `expired?` when the status
    enum has an `expired` value: it shadows the enum predicate; wall-clock
    staleness is `stale_quote?` (`quoted? && expires_at <= Time.current`).
  - **Gotcha — `listings.region` is the PROVINCE name** (`Listing#region_known`
    validates against `EsProvince` province names, not autonomous
    communities) — dev sample sellers carry `province:` accordingly.
- **Trust, content & compliance (Phase 7b)**:
  - **Static pages**: `PagesController#show` whitelist `PAGE_SLUGS`
    (about, how-it-works, selling, help, contact, seller-guides); unknown
    slugs 404, no Page model — copy lives in the templates/I18n
    (`pages.<underscored_slug>.*`). `/trust-and-safety` is a singular
    resource (`TrustsController`); stats via `Trust::Stats.visible`, each
    hidden below `Setting "min_public_stat"` (default 50, now seeded).
  - **Contact form**: `contact_messages_path` (POST only) stores
    `ContactMessage` (subject 1..140, body 10..5000, `locale` = request
    locale) + enqueues `ContactMailer` to `Setting "support_email"` (row is
    kept even with no support address; the mail is then simply not
    delivered). `rate_limit to: 5, within: 30.minutes`. Admin inbox is
    read-only; **the locale filter param is `lang`** — `params[:locale]`
    belongs to the routing segment and `?locale=xx` URLs 404.
  - **Reports**: one OPEN report per user per listing — partial unique
    index + a CUSTOM `no_open_duplicate` validation (errors `:already_reported`
    on `:user_id`; Rails 8.1's uniqueness validator always reports `:taken`
    in details, so it can't be used when callers key off a custom symbol).
    `close!(action, admin:)` validates the ACTION first, then raises
    `Report::InvalidTransition` on double-close. `FLOOD_THRESHOLD = 3` open
    reports on a live listing → `request_revalidation!` + admin e-mails.
    Admin closing = nested POST `report_resolutions` / `report_dismissals`
    (audited).
  - **Public legal pages**: `/legal/:slug` resolves locale → `en` →
    country default (`LegalPage.find_public` / `deliverable_slugs`);
    body rendered by `LegalPages::Render` with `{{placeholder}}` identity
    substitution + Commonmarker → `Rails::HTML5::SafeListSanitizer` allowlist
    (helper's `legal_markdown` returns `.html_safe` sanitized HTML — the
    raw sanitizer result is an UNSAFE String and `<%= %>` escapes it; and
    service objects can't use ActionView's `sanitize`, which needs the
    class-level sanitizer config).
  - **Cookie consent**: `cookie_consent` cookie = URL-encoded JSON
    `{version, categories, timestamp}`; `ApplicationController::CONSENT_VERSION = 1`
    (bump → banner again), `necessary` implicit, helpers
    `cookie_consent?` / `cookie_consent_needed?` / `cookie_consent_version`;
    Stimulus `cookie_consent_controller.js` + `shared/_cookie_consent` in
    the footer.
  - **Settings/queries**: `Setting.get_many(keys)` batches misses into ONE
    query (misses still not cached, so seeds take effect immediately);
    `IDENTITY_KEYS`/`FOOTER_KEYS` + `legal_identity(values = nil)` let the
    footer render with a single Setting read + one `deliverable_slugs`
    query (listings-index N+1 guard is ≤24 queries — layout reads count).
    Legal identity keys (legal_name, tax_id, registered_address,
    mercantile_registry_data, contact_email, dpo_email, phone, trade_name)
    are admin-editable on Site settings; blank ⇒ dashboard banner via
    `legal_identity_complete?`, never a hard block.
- **Legal seeds & review flag (Phase 7c)**: `legal_pages.needs_legal_review`
  (NOT NULL, default true) marks a text as an UNREVIEWED TEMPLATE. Loader
  `db/seeds/legal_pages.rb` upserts `db/seeds/legal/<COUNTRY>/<locale>/
  <slug>.md` (first line `# Title` → title, rest → body; published: true,
  needs_legal_review: true) and NEVER overwrites pages reviewed by an admin
  (false ⇒ skip + log). Admin: amber "Template — pending legal review" chip
  on index/edit, "Reviewed by legal counsel" checkbox (`legal_reviewed`
  virtual attr) flips it false on save (audited — update details include
  needs_legal_review); dashboard footnote counts published pages pending
  review (`DashboardStats#legal_pages_pending_review`, cached with stats).
  ES/es ships 8 Spanish templates (db/seeds/legal/ES/es/), ES/en their British-English translations (Spanish law still governs, Phase 7d) and GB/en a UK-law set (OSA 2023, UK GDPR + DPA 2018 + ICO, PECR, CCRs 2013, CRA 2015, DMCC Act 2024, Platform Operators Regs 2023/HMRC, E-Commerce Regs 2002 reg. 6 + Companies Act 2006 disclosure), using only the
  `Setting.legal_identity` placeholders and Spain/EU-accurate content
  (LSSI-CE, RGPD/LOPDGDD+AEPD, DSA, Reg. 2019/1150, TRLGDCU arts. 102–108
  & 120/RDL 7/2021, DAC7 Ley 13/2023, 48h buyer-protection window, 0% fees
  with ≥15 days notice, 3-business-day shipping); deliberately NO EU ODR
  reference (discontinued 2025). Country enable still gates on all 8 slugs
  published in the country's DEFAULT locale.


- **SEO (Phase 8a)**:
  - **Meta**: every public view calls `SeoHelper#set_meta` (title,
    description, canonical, OG incl. `product:price` for listings +
    `og:image` = `DEFAULT_OG_IMAGE` `/og-default.png` fallback, Twitter,
    hreflang). Canonical always strips `TRACKING_PARAMS`; browse/category/
    finder/store pages keep their filter params (sort + page=1 dropped);
    `es` is unprefixed so each page has one canonical. hreflang = 6
    locales + `x-default`, only on indexable pages. Layouts use
    `display_meta_tags site: site_name, reverse: true`.
  - **Robots**: `Seo` concern on ApplicationController — `NOINDEX_AREAS`
    (admin/sell/account/carts/checkouts/auth/conversations/offers/orders/
    favorites/…) get `robots: noindex,follow` meta + `X-Robots-Tag:
    noindex, follow` header. Dynamic view rules: `q` search, >2 facet
    groups (`seo_filtered_browse_count`: price band counts once, path
    category doesn't) and empty results are noindexed. Admin layout no
    longer hardcodes a robots tag — the concern is the single source.
  - **JSON-LD** (`JsonLdHelper`, `json_ld_tag` = `tag.script(payload.
    to_json.html_safe, type: "application/ld+json")`): NEVER add
    json_escape/gsub escaping — ActiveSupport already escapes `<`/`>`/`&`
    as `\u003c`… (test asserts a `</script>`-hostile title still parses
    and never contains a literal `</script>`). Home: Organization +
    WebSite (+SearchAction); listing show: Product+Offer (SoldOut when
    sold, itemCondition from condition enum, Brand from brand specs,
    seller org/person) + BreadcrumbList; category page 1: ItemList (24
    max) + BreadcrumbList; help: FAQPage; stores: Organization with
    AggregateRating only when `reviews_count > 0`.
  - **robots.txt is dynamic** (`RobotsController`, route outside the
    locale scope, static file DELETED): disallow-all unless
    `Rails.env.production? && Setting.search_engine_indexing?` (new
    Setting, DEFAULTS now **7 settings**, admin-editable on Site
    settings); when open: per-area `Disallow: /*/<area>` + `/<area>` +
    `Sitemap:` line pointing at `/sitemaps/sitemap.xml.gz`.
  - **Sitemap**: `config/sitemap.rb` — every URL in all 6 locale
    variants with `xhtml:link` alternates (gem renders attributes as
    `rel`/`href`/`hreflang` — assert in that order); output to
    gitignored `public/sitemaps/`; `SitemapRefreshJob` daily 3am
    (recurring.yml); tests use `SITEMAP_PUBLIC_PATH` temp dir + `APP_URL`.
  - **Error pages**: static `public/404|422|500.html` deleted,
    `config.exceptions_app = self.routes` (test + production),
    `ErrorsController` recovers the locale from
    `action_dispatch.original_path` (in the test env unrouted URLs still
    render DebugExceptions — assert localized content via `/404` with an
    explicit `env:` original_path).
  - **Listing slug history**: FriendlyId `:history` + 301 from old slugs
    in `ListingsController#show`.
  - **Brand assets** in `public/`: favicon.ico, icon-32/192/512.png,
    apple-touch-icon.png, og-default.png, site.webmanifest; all five
    layouts link them (theme-color meta in the application layout).

- **JSON API v1 (Phase 8b)** — `namespace :api { namespace :v1 }`, OUTSIDE
  the `(:locale)` scope (language via `Accept-Language`, never the URL; a
  `/es/api/v1` path must not route — asserted), `defaults format: :json`:
  - **Auth**: `Authorization: Bearer <ApiToken>` resolved by
    `Api::V1::BaseController#authenticate_token!` (`ApiToken.authenticate` —
    SHA-256 digest, `active` expiry scope, `last_used_at` stamp); banned
    → 403 `banned`. Public endpoints skip the callback and call
    `authenticate_token_if_present` (owners see their own drafts). `Current.api_token`
    is set and `Current.user` falls back to it, so all service objects keep
    working. Tokens come from `POST /session` (10/min/IP), `POST
    /registration`, or the admin panel; `GET/DELETE /api_tokens` manages
    them from the device; `DELETE /session` revokes.
  - **Error envelope is the only error shape**: `{ error: { code, message,
    details } }` — RecordNotFound→404 (outsiders ALWAYS 404, mirroring the
    web scoping: `current_user.orders`, `Conversation.for_user`, seller
    routes for buyers, etc.), RecordInvalid→422 with full per-attribute
    messages in `details`, ParameterMissing→400, `Api::V1::Forbidden`→403,
    `Listing::InvalidTransition`→409. Global throttle 300/min per token
    (IP when anonymous) → 429 `rate_limited`, same envelope.
  - **State changes = singular nested POST resources** mirroring the web
    (`submission`, `archival`, `sale_mark`, `acceptance`, `decline`,
    `withdrawal`, `shipment`, `payment_confirmation`, `delivery_confirmation`,
    `completion`, `cancellation`, `dispute`) — never magic PATCH flags.
    Business rules stay in the SAME service objects the web uses.
  - **Lists**: `meta.pagination` (`page/per_page/total/total_pages`) +
    `Link` header (`first/prev/next/last`); listings facets/echoed filters
    in `meta`; messages use a `?before_id=` cursor (chronological page).
    Catalogue/config get `fresh_when strong_etag:` → If-None-Match 304
    (STRONG validators only: Rack never echoes weak ETags back, so a weak
    one could never match its own If-None-Match).
  - **`GET /config`** is the native-client bootstrap: category tree,
    localized condition/sort/PC-finder labels, carriers, order statuses,
    `flags` (every `FeatureFlags::FEATURES` key as a boolean via Flipper),
    `min_app_version.{ios,android}` from two NEW nil-default Setting keys
    (`seed_defaults!` skips nil values — documented but never written until
    an admin sets them; nil = no forced update).
  - **Direct uploads**: `POST /api/v1/direct_uploads` mirrors the
    ActiveStorage engine's JSON (it is cookie+CSRF-only) and needs
    `include ActiveStorage::SetCurrent` (else the disk service cannot sign
    the PUT URL — "Missing host to link to!"). Client PUTs bytes to the
    returned url/headers (disk answers 204), then passes the `signed_id` in
    listing create/update `photos`.
  - **Devices + Cable**: `Device` (migration `20261118060000`: user FK,
    `push_token` ≤4096 unique per (user, push_token), platform ios|android;
    registry only — no sender wired yet); Action Cable accepts the SAME
    bearer token via `?token=` or Authorization header (session cookie
    stays as fallback for the web).
  - **CORS**: `rack-cors` — `/api/*` cross-origin only for `API_CORS_ORIGINS`
    (comma-separated env, unset = closed); exposes `Link`/`ETag`.
  - **Docs**: Redoc page `GET /api/v1/docs` + `GET /api/v1/openapi`
    (`send_file public/api/v1/openapi.yaml`, hand-maintained OpenAPI 3.1).
    `openapi_coverage_test` diffs routes↔spec both directions (verb-exact)
    so they can never drift; `route_actions_test` proves every api/v1 route
    constantizes to a real `action_method` (catches singular/plural and
    namespace mismatches) and pins the route count ≥60.
  - **Serializer**: `Api::V1::SerializationHelper` (explicitly `helper`-ed —
    `ActionController::API` auto-includes nothing) renders `price_money`
    triples (`cents/currency/formatted`), photo `card`/`full` variant URLs,
    web URLs carrying the NEGOTIATED locale (`default_url_options locale:`),
    and shared partials `api/v1/partials/_listing_card|_listing_full`.
    GOTCHA: iterating `listing.photos` yields `ActiveStorage::Attachment`
    (delegates to blob); `attached?` exists on neither — guard with
    `attachment.persisted? && attachment.blob&.persisted?`.
  - **API test plumbing** (`test/test_helpers/api_v1_test_helper.rb`,
    auto-included into integration tests): `auth_as(user)` + `get/post/
    patch/put/delete_json` (symbolized `json_body`, `auth_as: nil` sends no
    header), `api_token_for`, `use_token`, and `api_query_count` (N+1
    counter; COUNTS Rails 8.1 `cached: true` sql events — the per-connection
    query cache survives across requests in a test, and skipping them makes
    repeat requests count 0). Listings N+1 guard: limit 5 vs 100 within
    +1 (the 100-row page contains the labelled listings and AR skips the
    whole `Label` preload when a preload's join rows are empty — real data,
    not N+1) and ≤16 cap. Header GOTCHA: underscore names never become
    Rack env (`ACCEPT_LANGUAGE` is dropped) — send `"Accept-Language"`;
    Cable test helper is `assert_reject_connection`.

## Code map


| Area | Files |
| --- | --- |
| Routes (locale-scoped) | `config/routes.rb` — root `pages#home`, `resources :listings, only: %i[index show]` (nests `resources :offers, only: %i[new create]`), `resources :categories, only: :show, path: "c"`, `resources :stores, only: :show`, `get "search" → listings#index`, `namespace :sell { root "dashboards#show"; resources :listings + resource :submission/:archival/:sale_mark + resources :category_fields, only: :show; resource :dashboard; resource :store, only: %i[edit update]; resource :vacation, only: %i[create destroy]; resources :sales, only: %i[index show] }`, `resource :session`, `resources :passwords`, `resource :registration`, `resources :conversations, only: %i[index show create]` (nested `resources :messages, only: :create` + `resource :read_receipt, only: :create`), `resources :blocks, only: %i[index create destroy]`, `resources :offers, only: :index` + `resource :acceptance/:decline/:withdrawal` nested under offers; 4b: `resource :cart` + `resources :cart_items, only: %i[create update destroy]`, `resource :checkout, only: %i[show create]`, `resources :addresses`, `resources :orders, only: %i[index show]` (nested `resource :completion/:cancellation/:dispute` + `resources :delivery_confirmations, only: :create`), `namespace :sell { resources :sales { resource :payment_confirmation; resource :shipment; resource :cancellation } }`, `resource :stripe_webhook, only: :create`, `resources :reviews, only: %i[new create]`; 5: `resources :favorites, only: %i[index create destroy]`, `resources :stores, only: [] { resource :follow, only: %i[create destroy] }` (helper `store_follow_path(store)`), `resources :saved_searches, only: %i[index create update destroy]` (PATCH update toggles `email_alerts`), `resources :notifications, only: :index` + `resource :notifications_read, only: :create` (marks ALL read; controller is the plural-inferred `NotificationsReadsController`), `namespace :account { resource :profile/:security/:notification_preferences, only: %i[show update]; resource :data_export, only: :create; resource :deletion, only: %i[show destroy] }`; 7a: `resource :pc_finder, only: :show, path: "pc-finder"`, `resources :pc_finder_results, only: :index, path: "pc-finder/results"`, `resources :trade_in_quotes, only: %i[new create show], path: "sell-to-us" { resource :acceptance, only: :create, controller: "trade_in_acceptances" }`, admin `resources :trade_ins, only: %i[index show update]` |
| Auth | `app/controllers/concerns/authentication.rb` (cookie resume, `Current.session`), `sessions_controller.rb`, `passwords_controller.rb`, `passwords_mailer.rb` |
| Sign-up | `registrations_controller.rb` + `views/registrations/new` |
| User model | `app/models/user.rb` — `email_address` (normalized downcase, uniq index), `username` (uniq index, `/\A[a-zA-Z0-9_\-]{3,30}\z/`), `first_name`, `last_name`, `phone`, `role` enum (user:0 admin:1), `locale` (default "es"), `country_code` (default "ES"), `confirmed_at`, `banned_at` (`banned?/ban!/unban!`), `display_name`; has_many: store, listings, sales/orders, favorites, follows, seller_follows, saved_searches, conversations, offers, carts, reviews, sent_messages, api_tokens, devices |
| Locale switching | `application_controller.rb`, `config/application.rb`, `config/locales/*.yml`, `script/lint_locale_keys.rb` |
| Layout & chrome | `app/views/layouts/application.html.erb`, `_header.html.erb` (announcement, logo, search `GET /:locale?q=`, wishlist/notifications/cart icons, account dropdown, desktop mega menu + mobile slide-in menu, both cached per locale and busted by `Category.maximum(:updated_at)`), `_footer.html.erb` (7b rebuild: link columns + legal column from `LegalPage.deliverable_slugs`, support e-mail/phone + social links + blog URL read in ONE `Setting.get_many(FOOTER_KEYS)`, newsletter form, language switcher, copyright, cookie-consent banner), `_flashes.html.erb` |
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
| Wishlist & follows (5) | `app/controllers/{favorites,follows}_controller.rb` (Turbo Stream swaps `app/views/shared/{_favorite_button,_follow_button}.html.erb` in place), `favorite.rb` (`price_cents_at_save`, `#price_dropped?`/`#saved_price`, `with_listing_data` eager scope, counter cache), `follow.rb` (`follower`/`followed` on `follows`, self-follow rejected), wishlist page `app/views/favorites/index.html.erb` (dropped-since-saved badge) |
| Price drops & saved-search matching (5) | `app/services/listings/price_drop_notifier.rb` (`COOLDOWN` 24h via Notification-row re-query, only price CUTs on approved listings, mail gated by `wants_email?("price_drop")`), `app/services/saved_searches/match_new_listing.rb` (ancestor-category SQL prefilter + price-band check + `ListingSearch.new(params, only_id:).match?` — one code path with the results page), `app/jobs/saved_search_match_job.rb` (instant `SavedSearchMailer#match_found` ≤ once/user, `touch(:last_notified_at)` watermark), `app/jobs/saved_search_digest_job.rb` + `app/services/saved_search_digest.rb` (hourly via `config/recurring.yml` `saved_search_digest`, ≤10 listings, only matches past `last_notified_at`), `saved_search.rb` (`MAX_PER_USER` 25, JSONB `filters` + `search_params`, `attribute :email_alerts, default: false`, `with_alerts`); listing hooks in `listing.rb` (`after_update_commit :alert_price_drop`, `after_commit :match_saved_searches` on →approved transition) |
| Notification centre (5) | `app/controllers/{notifications,notifications_reads}_controller.rb`, `app/views/notifications/index.html.erb`, `app/views/shared/_unread_notifications_badge.html.erb` (header bell, `Notification.unread_count_for` cached per user), `app/helpers/notifications_helper.rb` (`notification_text`/`_icon`/`_link` from `KINDS` + payload), `notification.rb` (`KINDS`, `unsent_saved_search_matches`, `recent_unread_message_for?`, `unread_count_for`/`clear_unread_cache`/`mark_all_as_read_for`, `after_create_commit :bust_unread_cache_and_broadcast`) |
| Account area & GDPR (5) | `app/controllers/account/{base,profiles,securities,notification_preferences,data_exports,deletions}_controller.rb` (`layout "account"` = `app/views/layouts/account.html.erb` + `layouts/_account_nav.html.erb`; views `app/views/account/{profiles,securities,notification_preferences,deletions}/show.html.erb`), `user.rb` (`EMAIL_PREFERENCE_KEYS`/`DEFAULT_EMAIL_PREFERENCES` sparse-JSONB `wants_email?`, `update_notification_preferences`, virtual `current_password` for the security form), `app/services/users/anonymize.rb` (`OpenOrderError` + `open_orders_count` guard, `update_columns` anonymisation to `deleted-<id>@invalid`/`deleted-<id>` + hides the store, archives non-sold/non-archived listings incl. drafts), `app/services/users/data_export.rb` (account JSON) + `app/services/users/data_export_job.rb` (`Users::DataExportJob`, attaches `user.export` blob, 7-day signed link); mailers `price_drop_mailer.rb`/`saved_search_mailer.rb` (`match_found` + `digest`)/`data_export_mailer.rb` + `app/views/{price_drop_mailer,saved_search_mailer,data_export_mailer}/*` (recipient locale) |
| Admin panel (6a) | `app/controllers/admin/*` — `base_controller.rb` (`layout "admin"`, `require_admin!`: non-admin → 404, banned admin → sign-in page), `auditable.rb` (`audit!` → `AdminAuditLog`), `dashboards` + `admin/dashboard_stats.rb` (`Result` struct; `oldest_pending_listings`/`latest_signups` are CLASS methods), `moderations` (queue + cockpit with `Listing.potential_duplicates_of` pg_trgm hints) + `moderations/{approve,reject,bulk}.rb` (transition + Notification + `ModerationMailer` + ModerationEvent; `Reject::REASONS` keys under `admin.rejections.reasons.*`), `approvals`/`rejections` (new+create)/`bulk_moderations` (one aggregate audit row/batch), `listings` (+`admin/listing_filter.rb`, CSV via `listings/csv_export.rb` → `send_data` a String, edit via `listings/admin_update.rb`) + `unpublications.rb`, `searches` + `admin/global_search.rb`, `users` (+`admin/user_filter.rb`, role guards in `users/admin_update.rb`: returns `:last_admin`/`:cannot_demote_self`, SKIPS save when blocked), `bans` (new/create/destroy via `users/ban.rb` — destroys sessions + api_tokens + archives approved listings / `users/unban.rb`), `impersonations` (create = new session for non-admin target + `session[:impersonator_id]`; destroy skips `require_admin!` and re-auths the impersonator; banner `shared/_impersonation_banner`, `impersonation_target` helper in ApplicationController), `stores` + `verifications`/`hidings` (POST/DELETE `admin_store_verification_path`/`admin_store_hiding_path`), views `app/views/admin/**` (+ `admin/shared/{_events,_seller_card}`), model `admin_audit_log.rb` (append-only), helpers `app/helpers/admin/*` (sidebar/status), Stimulus `moderation_controller.js` (queue checkboxes) + `rail_controller.js`; tests `test/controllers/admin/{access,listings,moderations,stores,users}_test.rb` + `test/services/admin/dashboard_stats_test.rb` |
| Admin panel (6b) | controllers `app/controllers/admin/`: `orders` (index via `admin/order_filter.rb` + search, show, `update` = `Orders::ForceTransition` — audited forced status transition with reason), nested `notes` (internal order notes), `disputes` (queue) + nested `resolutions` (new/create → `app/services/disputes/resolve.rb`: refund via `Payments::StripeRefund` when `payment_reference` else direct mark, notify buyer+seller; via `Order#refund!`/`#release_to_seller!` + `refund_cents`), `reviews` (index filters; `destroy`=hide with REQUIRED reason; `Review#hide!/unhide!/visible/hidden`), `categories` (tree, translated names/seo_descriptions tabs) + nested `positions` (`Category#move!` up/down) + `category_spec_attributes` (M2M attach/update/detach), `spec_attributes` (CRUD; `key` immutable — `activerecord.errors.messages.immutable`), nested `spec_options` + `spec_option_merges` (merge rewrites `listings.specs` in one UPDATE; delete blocked while in use) + `bulk_options` (one per line), `labels`/`seller_tags` CRUD, `countries` (edit + enable gated by `Country` validation `missing_legal_pages` vs `LegalPage::SLUGS` (6) published in the country's locale; `missing_legal_slugs` helper), `feature_flags` (registry `FeatureFlags::FEATURES` + `warning_for` (soft, never blocks) + `register_all!` in `config/initializers/flipper.rb`), `settings` (singular; `admin/settings.rb` `Update` validates all fields before ANY write; errors `admin.settings.edit.errors.*`; `maintenance_mode` → `ApplicationController#enforce_maintenance_mode` 503 `application/maintenance`, Admin module + admins bypass), `legal_pages` CRUD (markdown via `legal_pages_helper.rb`), `newsletter_subscriptions` (index + CSV via `app/services/csv_builder.rb` + destroy), `audit_logs` index; `TranslatableJsonb#assign_translations` + controllers `permit(names: {})` pattern; views `app/views/admin/{orders,disputes,resolutions,reviews,categories,category_spec_attributes,spec_attributes,spec_options,labels,seller_tags,countries,feature_flags,settings,legal_pages,newsletter_subscriptions,audit_logs}/*`; tests `test/controllers/admin/{orders,reviews,categories,category_spec_attributes,spec_attributes,spec_options,labels,seller_tags,countries,feature_flags,settings,legal_pages,audit_logs,page_render,notes}_test.rb` + `test/services/{disputes_resolve,csv_builder}_test.rb` (page_render covers the orders/disputes screens) |
| PC Finder & performance (7a) | `app/services/performance/{scorer,fps_estimator}.rb` (module class methods; tier/game tables `config/data/{gpu_tiers,cpu_tiers,games}.yml`), `app/services/pc_finder/search.rb` (`PER_PAGE` 9, `sample_for`, value-ordering), `app/controllers/{pc_finders,pc_finder_results}_controller.rb` (unauthenticated), `app/views/pc_finders/show.html.erb` (quiz, GET form progressive-enhanced) + `app/views/pc_finder_results/{index,_result,_page}.html.erb` (locale scopes `result:`/`page:` — no leading underscore!), `app/views/pages/home/_finder.html.erb`, `app/javascript/controllers/quiz_controller.js`, `app/views/shared/_performance_bar.html.erb` (cards + `listings/show`), `lib/tasks/performance.rake` (`performance:backfill`); listing hooks `refresh_performance_score` + public `scorable_category?` in `listing.rb`; migration `20261118020002` (partial index on `performance_score`) |
| Sell-to-us trade-ins (7a) | `app/models/trade_in.rb` (enums, `TRANSITIONS` + `transition_to!`/`expire!` → `TradeIn::InvalidTransition`, `QUOTE_TTL` 7d, `stale_quote?` — NOT a custom `expired?`, that shadows the enum predicate), services `app/services/trade_ins/{quote,accept}.rb`, pricing `config/data/trade_in_prices.yml`, controllers `trade_in_quotes_controller.rb` (`/sell-to-us` new/create/show) + `trade_in_acceptances_controller.rb` (POST nested under the quote) — both `head :not_found` unless Flipper `:sell_to_us` — `app/controllers/admin/trade_ins_controller.rb` (index/show/audited update) + `app/views/trade_in_quotes/{new,show}.html.erb`, `app/views/admin/trade_ins/{index,show}.html.erb`, sidebar entry in `app/helpers/admin/sidebar_helper.rb`; migration `20261118020001` |
| Trust, content, reports & consent (7b) | `app/controllers/{trusts,legal_pages,pages,contact_messages}_controller.rb` + `app/controllers/admin/{reports,report_resolutions,report_dismissals,contact_messages}_controller.rb`, `app/views/pages/{about,how_it_works,selling,help,contact,seller_guides}.html.erb`, `app/views/trusts/show.html.erb` + `app/services/trust/stats.rb` (min_public_stat gate), `app/views/legal_pages/show.html.erb` + `app/services/legal_pages/render.rb` + `app/helpers/legal_pages_helper.rb` (`legal_markdown`: Commonmarker + explicit `Rails::HTML5::SafeListSanitizer` allowlist, returns html_safe), `app/models/{contact_message,report}.rb` (Report: reason enum, `open?`/`close!`, `no_open_duplicate` → `:already_reported`, `FLOOD_THRESHOLD` 3 → `request_revalidation!` + `ReportMailer`), `app/mailers/{contact_mailer,report_mailer}.rb` + views, `app/views/reports/new.html.erb` (report form on listings), `app/views/admin/{reports,contact_messages}/*`, `app/javascript/controllers/{cookie_consent,faq_filter}_controller.js`, `app/views/shared/_cookie_consent.html.erb`, consent helpers in `application_controller.rb` (cookie JSON `{version, categories, timestamp}`, `CONSENT_VERSION` 1); routes: `resource :trust` (`/trust-and-safety`), `resources :pages, param: :slug`, `resources :legal_pages, param: :slug, path: "legal"`, `contact_messages` (public create + admin index/show), `resources :reports` nested under listings (new/create) and under admin (index/show + `resource :resolution/:dismissal`); migrations `20261118030001`/`030002` (partial unique index on open reports) |
| Legal seeds & review (7c) | migration `20261118030003` (`legal_pages.needs_legal_review` NOT NULL default true); `legal_page.rb` (`pending_legal_review` scope, `legal_reviewed` virtual inverse attr); `db/seeds/legal_pages.rb` loader (upsert from `db/seeds/legal/<COUNTRY>/<locale>/<slug>.md`, `# Title` first line, published+needs_legal_review true, skips admin-reviewed pages) wired into `db/seeds.rb`; 8 ES/es templates `db/seeds/legal/ES/es/{terms,privacy,cookies,legal_notice,returns,buyer_protection,seller_terms,prohibited_items}.md` (Spain/EU-accurate, identity placeholders only, ≥4 `##` each, italic template note); admin legal pages index/edit amber `pending_review_chip` + form `legal_reviewed` checkbox (update audit details now include `needs_legal_review`); `Admin::DashboardStats#legal_pages_pending_review` + dashboard footnote `footnote.legal_pending_review` |
| JSON API v1 (8b) | `app/controllers/api/v1/base_controller.rb` (bearer auth + `authenticate_token_if_present`, `render_error` envelope + the five `rescue_from`s, 300/min `rate_limit` by token/IP, `set_link_header`, `api_country_code`, Accept-Language `set_locale`, `page_size` 1–100 default 20, `default_url_options locale:`), 40 endpoint controllers + `api/v1/sell/{dashboards,listings,submissions,archivals,sale_marks}_controller.rb`, `app/errors/api/v1/forbidden.rb`, `app/helpers/api/v1/serialization_helper.rb` (price/photo/store/logo/avatar + pagination `meta`, shared partials `app/views/api/v1/partials/_listing_card.json.jbuilder` + `_listing_full.json.jbuilder`), views `app/views/api/v1/**`, `docs_controller.rb` (Redoc `show` + `send_file` openapi) + `public/api/v1/openapi.yaml` (OpenAPI 3.1, hand-maintained), `config/initializers/cors.rb` (`rack-cors`, `API_CORS_ORIGINS`, exposes Link/ETag); routes: `namespace :api/:v1` outside the locale scope, `defaults format: :json` (see the block in `config/routes.rb`) |
| API auth, devices, cable (8b) | `api_token.rb` (unchanged Phase 1 model — `issue_for`/`authenticate`/`active`/`expired?` now load-bearing), `current.rb` (`attribute :api_token`; `user` falls back to `session&.user`), `device.rb` (PLATFORMS, push_token unique per user) + migration `20261118060000`, `user.rb` `has_many :devices`, `offer.rb` `has_one :seller, through: :listing` (serializers/eager loads), `app/channels/application_cable/connection.rb` (bearer via `params[:token]` or Authorization header → ApiToken, session cookie fallback); `setting.rb` gained nil-default `min_app_version_ios/android` (`seed_defaults!` skips nil values) |
| SEO & error pages (8a) | `app/controllers/concerns/seo.rb` (`NOINDEX_AREAS` → robots meta + `X-Robots-Tag` header), `app/helpers/seo_helper.rb` (`set_meta`, canonical/hreflang params, `TRACKING_PARAMS`/`FILTER_PARAMS`, `DEFAULT_OG_IMAGE`), `app/helpers/json_ld_helper.rb` (builders + `json_ld_tag` — raw `to_json`, no extra escaping), `app/controllers/robots_controller.rb` (dynamic robots.txt) + `app/controllers/errors_controller.rb` (`/404|422|500`, locale from `action_dispatch.original_path`) + `app/views/errors/*` + `layouts/errors.html.erb`, `config/sitemap.rb` (6-locale variants + `xhtml:link` alternates) + `app/jobs/sitemap_refresh_job.rb` (recurring 3am), `Setting.search_engine_indexing?`, FriendlyId `:history` on `listing.rb` + 301 in `ListingsController#show`, `config.exceptions_app = self.routes` (test+prod), brand assets `public/{favicon.ico,icon-32/192/512.png,apple-touch-icon.png,og-default.png,site.webmanifest}`, tests `test/integration/{seo,robots_txt,sitemap,error_pages,listing_slug_history}_test.rb` |
| Platform | `country.rb` (JSONB-free locale rows via `name_key` i18n keys, `Country.seed_defaults!` ES-only), `setting.rb` (`get/set/get_many` + Rails.cache key `settings/<key>`, `DEFAULTS` now incl. `min_public_stat` and the 8b `min_app_version_ios/android` (nil default ⇒ documented in DEFAULTS, never seeded; `seed_defaults!` skips nil values), `IDENTITY_KEYS`/`FOOTER_KEYS`, `legal_identity(values = nil)`/`legal_identity_complete?`), `api_token.rb` (`issue_for` → SHA-256 `token_digest`, `authenticate` active-only), `legal_page.rb` (+ `find_public` / `deliverable_slugs` locale-fallback chain, 7b), `newsletter_subscription.rb`, `notification.rb`, `saved_search.rb`, `money.rb` (value object: `cents`/`amount`/`to_s`) |
| Seeds (Phase 2a) | `db/seeds.rb` (loads `db/seeds/support/seed_loader.rb` + one loader per concern, idempotent upserts), raw data `db/seeds/data/{categories,spec_attributes,category_spec_attributes,labels,seller_tags}.yml` — counts: 61 categories, 34 spec attributes, 293 options, 88 category attachments, 13 labels, 24 seller tags (+air-cooling/aio-cooling/competitive in Phase 7a), 6 countries, 7 settings (4 core + `min_offer_percent` since Phase 4a + `min_public_stat` since Phase 7b + `search_engine_indexing` since Phase 8a; since Phase 8b `Setting::DEFAULTS` carries 9 keys — the two `min_app_version_*` have nil defaults and are never written) |
| Seeds (Phase 2b → replaced by Phase 9) | `db/seeds/sample_listings.rb` and the `*@pcmarket.test` sample dataset are **gone**: `DemoSeed.cleanup_legacy_samples!` (in `db/seeds/demo.rb`) destroys those users + orphan `friendly_id_slugs` rows once; dev DBs now carry the Phase 9 dataset below |
| Demo seed & image APIs (Phase 9) | `db/seeds/demo.rb` (`module DemoSeed`, `run!(count:)` — called from `db/seeds.rb` in dev or `SEED_DEMO=1`; refuses production unless `ALLOW_DEMO_SEED=1`; `SEED_LISTINGS` default 300, `SEED_RESET=1`, `SEED_SEED=` RNG; **idempotent** fixed emails `*@demo.pcmarket.test` — 1 admin + 8 business + 40 sellers + 60 buyers, top-up semantics: re-running leaves exactly N listings); catalog `db/seeds/data/demo_catalog.yml` (52 leaves: models + € price ranges + spec presets, prices stored as euros → seed ×100; `query` key optional, defaults to category slug); business stores get valid **CIFs via `SpanishTaxIdValidator.cif_control`** + ImageMagick logo/banner (attached with `identify: false` + explicit `{width:,height:}` metadata — `vite_image_tag` requires dimensions and analyzer jobs are skipped on that path) + policy pages; full social/commerce graph (orders walked through the real state machine then backdated via `update_columns`; disputes opened BEFORE backdating; reports ≤3/listing to avoid flood revalidation; offers accepted via `accept!`). Image services `app/services/demo_images/{fetcher,placeholder,providers/*}.rb`: `Fetcher.fetch(title:, query:, category:)` → `Result(path:, attribution:, source:, content_type:)`, provider order Pexels→Pixabay→Openverse (last two keyless-gated by `PEXELS_API_KEY`/`PIXABAY_API_KEY`), pool cache `tmp/demo_images/<query-slug>/manifest.json`, magic-byte validation + 8 MB cap + 10 s timeouts in `Providers::Base.get_json` (custom UA `PCMarketSeed/1.0` — Cloudflare 403s Ruby's default), 3 s Openverse throttle (`min_call_interval` test seam), **Unsplash deliberately not integrated** (render-time hotlink counting incompatible with seed-time downloads — rationale in `providers/base.rb`); `Placeholder` (ImageMagick, absolute-path fonts only on this box) always succeeds offline. Attribution lives in `blob.metadata["attribution"]` (STRING keys!) rendered by `ListingsHelper#photo_credit_tag` ("Foto: X · BY-SA vía openverse") under each gallery slide (`listing.photo_credit` in 6 locales); `photo:` tallies in `DemoSeed.report` = `openverse:Npx/…` per-source counts |
| Migrations | Phase 0: `20261116205301…205400`. Phase 1 domain: `db/migrate/20261117090001`–`20261117090033` (countries, settings, stores, categories, spec_*, listings + tsv trigger/GIN, labels/tags/moderation, favorites/follows, saved_searches, conversations/messages/blocks, offers, carts/cart_items, addresses/orders/order_items, reviews, notifications, newsletter, legal_pages, api_tokens, user ban fields, active_storage). Phase 3b: `20261117200001` (stores: returns/shipping policies, shipping-default cents), `20261117200002` (friendly_id_slugs), `20261117200003` (stores.city/region). Phase 4a: `20261117210001` (messages: `kind` enum + `offer_id` FK), `20261117210002` (listings: `reserved_for_id` FK + `reserved_until`). Phase 4b: `20261117223000` (orders: `paid_at/completed_at/cancelled_at` datetimes + `checkout_token` string + indexes on `checkout_token`/`status`; `shipped_at`/`delivered_at` already existed since Phase 1). Phase 5: `20261117230001` (favorites: `price_cents_at_save` integer), `20261117230002` (users: `notification_preferences` jsonb NOT NULL default `{}`), `20261117230003` (stores: `hidden` boolean NOT NULL default false — set on GDPR anonymisation; `Store.visible` excludes them). Phase 6a: `20261118010001` (pg_trgm extension + GIN index on `listings.title` for `Listing.potential_duplicates_of`), `20261118010002` (`admin_audit_logs`: admin_id FK, polymorphic subject, action, details jsonb). Phase 6b: `20261118015001` (`order_notes`: order + admin FKs, body), `20261118015002` (orders `refund_cents`), `20261118015003` (reviews `hidden_at` — hidden reviews excluded from public + rating counters via `visible/hidden` scopes). Phase 7a: `20261118020001` (`trade_ins`: optional user FK — null while the quote is anonymous — component_type/condition/status enums, `model`, `has_box`, `offered_cents`, `expires_at`, indexes on status/expires_at), `20261118020002` (partial index on `listings.performance_score WHERE NOT NULL`). Phase 7b: `20261118030001` (`contact_messages`: name/email/subject/body + `locale`, index on created_at), `20261118030002` (`reports`: listing/user FKs, reason enum, `details`, `resolved_at/resolved_action/resolved_by_id` + **partial unique index (listing_id, user_id) WHERE resolved_at IS NULL**). `saved_searches.email_alerts`/`last_notified_at` already existed since Phase 1 migration `20261117090017`. Phase 7c: `20261118030003` (legal_pages `needs_legal_review` boolean NOT NULL default true). Phase 8b: `20261118060000` (`devices`: user FK NOT NULL, `push_token`/`platform` NOT NULL strings, unique index (user_id, push_token)). Schema dump: `db/structure.sql` (schema_format: sql in `config/database.yml`) |
| Tests | `test/models/user_test.rb`, `test/models/{listing,category,setting,country,api_token,review,favorite}_test.rb`, `test/models/store_test.rb` (3b: name/description/VAT/business/region/logo/banner validations, slug history — create via model, not fixtures), `test/validators/spanish_tax_id_validator_test.rb` (NIF/NIE/CIF vectors incl. G02377372, P0200000H), `test/services/{commission_calculator,listing_search,sell/dashboard_stats}_test.rb` (dashboard: windowed revenue nets commission, zero-filled ISO weeks, unanswered/pending scopes; fixture order `one` is a completed in-window order for seller two and orders' `created_at` defaults to now), `test/controllers/{pages,listings,categories,stores,sessions,passwords}_controller_test.rb`, `test/integration/sell_listings_test.rb` (3a + photo purge-after-commit regression: failed update keeps photos attached), `test/integration/sell_dashboard_test.rb` (auth, KPI render, attention), `test/integration/sell_store_settings_test.rb` (euro fields, business VAT, oversized logo 422, rename → 301 via seeded `slugs` row), `test/integration/sell_vacation_test.rb` (toggle, listing notice/disabled buy, store banner), `test/helpers/listings_helper_test.rb`, `test/test_helpers/session_test_helper.rb` (`sign_in_as`); fixtures for users (incl. `banned`)/countries/categories/spec_*/labels/seller_tags/stores/listings/orders/order_items/files. `test_helper.rb`: `I18n.default_locale = :en`, `routes.default_url_options[:locale] = :en`, and a **global** `setup { Listing.reindex_search_vectors! }` (fixture INSERTs do not fire `trg_listings_tsv`, which only fires on UPDATE of title/description) and `setup { Rails.cache.clear }` (Rails.cache is NOT transactional — a rolled-back `Setting.set` would otherwise leak its cached value, e.g. maintenance_mode, into the next test in the worker). GOTCHA: fixture orders use `number:` `PCM-2025-000001/2` (deliberately NOT `PCM-2026-*`: fresh `order_number_seq` nextvals are 1,2 and would collide with same-year fixture numbers when tests create orders); create extra orders in tests with an explicit unique `number:` or let `assign_number` pick from the sequence. `listings_controller_test.rb` also guards against N+1 by counting `sql.active_record` notifications. Phase 4a: `test/models/{conversation,message,offer}_test.rb`, `test/services/{conversations/start,messages/send}_test.rb`, `test/services/offers/{create,decisions}_test.rb`, `test/jobs/expire_offers_job_test.rb`, `test/mailers/message_notification_mailer_test.rb` (mailer renders in the RECIPIENT's locale — fixture user `one` is `es`), `test/integration/messaging_test.rb` (scoping, start refusals, read receipts, blocks incl. `cannot_block_self`/`taken`, 30/min → 429 via `MessagesController::RATE_LIMIT_STORE.clear` in setup), `test/integration/offers_test.rb` (form hints in `:en` money format `€300.00`, decision flows, reserved 422 + banner, tab scoping), `test/integration/turbo_broadcasts_test.rb` (`capture_turbo_stream_broadcasts` returns Nokogiri elements — assert `el["action"]`/`el["target"]`/`to_html`; commit callbacks DO fire in transactional tests on this Rails). Phase 4b: `test/models/{cart,order}_test.rb`, `test/services/{carts_add_item,carts_merge,carts_summary,checkout_place_orders,checkout_direct_payment,payments_stripe_checkout}_test.rb` (PlaceOrders covers per-seller split + recomputed totals, commission flag off/on, free-shipping threshold, pickup, the concurrency guard — a `Listing.singleton_class.define_method(:find)` swap sells the listing mid-transaction → `:not_purchasable` + zero orders — and token replay), `test/jobs/auto_complete_orders_job_test.rb`, `test/controllers/{carts,checkouts,orders,stripe_webhooks}_controller_test.rb` + `test/controllers/sell/sales_controller_test.rb` (role guards: buyer hitting seller routes 404, outsider 404, seller can't confirm delivery). Fixtures add `carts.yml`, `cart_items.yml`, `addresses.yml` (address columns: `full_name/line1/line2/city/region/postal_code/country_code/phone/default`). **Minitest 6 has no `minitest/mock`** — no `stub`; swap class methods via `Klass.singleton_class.define_method(...)` + `remove_method` in `ensure` (see Stripe stubs). Integration tests can't read signed cookies — guest carts via `Cart.where(user: nil).order(:id).last`, assert `cookies[:cart_token].blank?` after login. `perform_enqueued_jobs` needs `include ActiveJob::TestHelper`. Test env uses `config.cache_store = :memory_store` (message rate limiter needs a real store). Phase 5: `test/integration/{favorites,follows,saved_searches,notifications,account_settings}_test.rb`, `test/services/listings/price_drop_notifier_test.rb`, `test/services/saved_searches/match_new_listing_test.rb`, `test/services/users/{anonymize,data_export}_test.rb`, `test/mailers/phase5_mailers_test.rb` (no favorites/follows/notifications/saved_searches FIXTURE files — those tests create records in setup). Phase 5 mail-test gotchas: NullMail must assert on `…action.message` (lazy `MessageDelivery`), multipart body assertions use `text_part.body.decoded`, absolute delivery counts need `ActionMailer::Base.deliveries.clear` in setup. Phase 7b: `test/models/{contact_message,report}_test.rb` (report flood → `request_revalidation!` + one e-mail per admin, `close!` arg-then-state guards, `:already_reported` on duplicate OPEN reports — closed ones free the slot), `test/controllers/{contact_messages,admin/contact_messages,reports,admin/reports}_controller_test.rb` (contact: locale capture, 6th message in 30 min rate-limited, no-support-address keeps the row but delivers nothing; admin inbox: `lang` filter + bogus locale ignored), `test/controllers/{legal_pages,trusts}_controller_test.rb` (public fallback chain es→en→country default, min_public_stat gating, hostile markdown never reaches the page), `test/controllers/cookie_consent_test.rb`, `test/controllers/admin/dashboards_controller_test.rb` (legal-identity banner); `admin/access_test.rb` gained `access_report`/`access_contact_message`. GOTCHA: `assert_enqueued_emails` counts enqueued mail jobs, and commit callbacks fire in transactional tests — count enqueue deltas around `after_create_commit` hooks. Phase 7c: `test/seeds/legal_pages_seeds_test.rb` (loader `load`ed against a temp seed dir — creates pages published+pending-review, title/body split from the H1, re-seed idempotent, admin-reviewed pages never overwritten); `test/controllers/admin/legal_pages_controller_test.rb` (amber chip shown/hidden, checkbox markup, PATCH `legal_reviewed=true` → needs_legal_review false + update audit details include it); `test/services/admin/dashboard_stats_test.rb` (pending-review count ignores drafts + reviewed); `test/models/country_test.rb` (legal enable gate counts the country's DEFAULT locale only). Phase 8b: `test/integration/api/v1/{auth,devices,config,listings,engagement,conversations_messages,offers,cart_checkout,orders_transition,sell,throttling,openapi_coverage,route_actions}_test.rb` (13 request specs, one area each) + `test/channels/application_cable/connection_test.rb` (bearer `params: { token: }` accept/reject, `assert_reject_connection`); shared plumbing `test/test_helpers/api_v1_test_helper.rb` (`auth_as`, verb helpers, symbolized `json_body`, `api_query_count`). GOTCHAs: underscore header names never become Rack env vars (send `"Accept-Language"`); `api_query_count` counts Rails 8.1 `cached: true` sql events (per-connection query cache survives across requests — skipping them makes repeat requests count 0); the listings N+1 guard allows +1 queries between limit 5 and 100 (the bigger page's labelled listings trigger a `Label` preload AR skips when the join rows are empty) with a hard cap of 16; direct-upload tests must PUT the bytes to the returned signed disk URL (204) before attaching the signed_id — fixture blobs have no bytes on disk |

## Open items (next phases)

- Phase 6 (admin parts 1+2) is complete: moderation, listings, users, stores,
  dashboard + audit writing (6a); orders/forced transitions/notes, dispute
  refunds, review hiding, taxonomy + spec option merges, country toggles +
  legal-page gate, feature flags, settings + maintenance mode, legal pages,
  newsletter CSV, audit-log browse (6b). Still open from the admin backlog:
  commissions/fee overview page, re-instatement of a banned seller's archived
  listings from the admin UI, seller anonymisation trigger from admin (the
  GDPR `Users::Anonymize` service exists).
- Seller follow-ups: per-listing edit of labels. (Listing create/edit,
  publish flow, photo upload, mark-sold and archiving shipped in Phase 3a;
  store settings, dashboard, vacation mode and a read-only sales list shipped
  in Phase 3b — fulfilment actions and payments shipped with Phase 4b
  checkout; payout UI still open. Wishlist/favourites, store follows, saved
  searches + alerts and the notification centre shipped in Phase 5.)
- Cart + checkout + order lifecycle shipped in Phase 4b (guest carts + login
  merge, per-seller orders, direct payment + Stripe behind flag `stripe_checkout`,
  full state machine with role-guarded transitions, auto-complete/auto-cancel job,
  reviews on completed orders). Dispute handling + admin refund action shipped
  in Phase 6b (resolutions with Stripe refund / release-to-seller).
  Follow-ups: payout/wallet UI, real Stripe keys/webhook endpoint wiring in
  production.
- Sell-to-us trade-ins shipped in Phase 7a (quote → sign-in + accept →
  admin-fulfilled shipment walk, all behind flag `sell_to_us`). Follow-ups:
  e-mails/status notifications for trade-ins, shipping-label generation,
  reselling inspected trade-in parts as listings, public status lookup.
- Trust/content/compliance shipped in Phase 7b (trust page, six content
  pages, contact form + admin inbox, listing reports + admin resolution
  inbox, public legal delivery with locale fallback, cookie consent,
  footer rebuild, legal identity in settings). Follow-ups: analytics
  scripts wired behind `cookie_consent?("analytics")` (the plumbing exists,
  no script ships yet), report outcomes notifying the reporter, admin
  reply form for contact messages (answers currently go out-of-band via
  the support e-mail copy), richer report evidence (screenshots).
- Legal seeds + review workflow shipped in Phase 7c (`needs_legal_review`
  flag, `db/seeds/legal/<COUNTRY>/<locale>/*.md` loader that never
  overwrites reviewed pages, admin "Reviewed by legal counsel" checkbox,
  dashboard pending-review footnote). Follow-ups: ALL 8 Spanish templates
  still need a real lawyer pass (every seeded page is `needs_legal_review:
  true` — a non-zero dashboard footnote is a launch blocker); fill the
  identity Settings (`operator_legal_name`, `tax_id`, `registered_address`,
  `mercantile_registry_data`, contact/DPO e-mails) before launch, the
  `{{…}}` placeholders render as blank otherwise; legal docs for the other
  countries' DEFAULT locales (EN for GB, plus FR/DE/IT/PT) still need to be
  seeded before those countries can pass the enable gate.
- Google login (flag `google_login`), email confirmation (`confirmed_at` exists but is unused).
- JSON API v1 shipped (Phase 8b). Follow-ups: push delivery (the `Device`
  registry collects tokens, nothing sends yet), OAuth-style token exchange /
  refresh flow, and any `Link`-header discovery for cursor-paginated messages.
- Seed data: reference data done (Phase 2a) and dev demo catalogue done (Phase 2b,
  dev-only). Photo placeholders are generated gradients — replace with real assets if
  screenshots/design reviews matter. pg_search typo tolerance (dmetaphone) if needed.
- Saved searches UI, notification inbox, wishlist, follows and account area
  (profile/security/e-mail prefs/GDPR) shipped in Phase 5; store-page review
  display (Phase 2b) + write-a-review (Phase 4b). Chat follow-ups: message
  edit/delete, typing indicators, photo-in-chat. Notification follow-ups:
  per-item read state (only mark-all-read exists today), in-app e-mail
  preference nudges.
- Add `script/lint_locale_keys.rb` to CI.
