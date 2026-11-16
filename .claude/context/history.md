# History

## 2026-11-16 — Fix: shared-cache leak on listing and store pages

**What changed**

- `ListingsController#show`: `fresh_when(..., public: true)` is now
  `public: Current.user.nil? && (@listing.approved? || @listing.sold?)`, plus
  `cache_control: { max_age: 0, must_revalidate: true, private: !shared_cacheable }` so
  the private side is stated explicitly instead of relying on the framework default.
  Same treatment in `StoresController#show`, where the visibility half of the rule is
  simply `Current.user.nil?` (a storefront only ever lists approved listings, but the
  layout header is personalised).
- Audited the rest: `CategoriesController#show` and `PagesController#home` never call
  `fresh_when`/`expires_in`, so they already emit `max-age=0, private, must-revalidate`
  — nothing to change there (verified by a temporary header probe).
- Tests (`test/controllers/listings_controller_test.rb`,
  `test/controllers/stores_controller_test.rb`): anonymous GET of an approved listing /
  store → `Cache-Control` matches `/\bpublic\b/` and not `private`; signed-in owner GET
  of a draft listing, admin GET of a pending one, signed-in GET of a sold listing and
  signed-in store GET → match `/\bprivate\b/` and not `public`.

**Why**

`public: true` told CDNs and proxy caches they may store the response, but two slices of
it are not shared-safe: signed-in visitors get a personalised header
(`layouts/_header.html.erb` uses `authenticated?`), and owners/admins can open
draft/pending_review/rejected listings. A shared cache could therefore hand one visitor's
page to another. The ETag already varies with `Current.user.present?`, so the fix costs
nothing for anonymous traffic. Note reserved listings now fall on the private side
(`set_listing` shows them publicly, the cache rule does not publish them) — deliberate,
they still revalidate via ETag/`Last-Modified`.

**Files touched**

- `app/controllers/listings_controller.rb`, `app/controllers/stores_controller.rb`
- `test/controllers/listings_controller_test.rb`, `test/controllers/stores_controller_test.rb`
- `.claude/context/{history,project}.md`

**Verification** `bin/rails test` → 138 runs / 879 assertions / 0 failures / 0 errors;
`bin/rubocop` → 138 files, 0 offences. Probed headers: anonymous listing/store
`max-age=0, public, must-revalidate`; owner draft and signed-in store
`max-age=0, private, must-revalidate`; category and home pages
`max-age=0, private, must-revalidate` (unchanged).

## 2026-11-16 — Phase 2b: public browsing (search, categories, listing and store pages)

**What was built**

- `ListingSearch` service (`app/services/listing_search.rb`) — the only place public
  queries are built. Params: `q`, `category` (self + descendants; unknown slug → `none`),
  `min_eur`/`max_eur` (→ integer cents), `condition[]`, `f[attr][]` (OR within an
  attribute via jsonb containment / `jsonb_array_elements_text`, AND across attributes),
  `labels[]`, `tags[]`, `seller` (store slug), `sort`
  (`best_match|newest|price_asc|price_desc|most_favorited`), `page`. Returns a `Result`
  struct (`records, pagy, total_count, facets, facet_attributes, filters`) plus
  `#facet_count`, `#spec_facets`, `#applied_filters?`, `#empty?`. Facet counts are
  **one** query (`WITH scoped AS (…) UNION ALL` over condition::text, label/tag joins on
  slug and jsonb spec expansion), computed before pagination. Featured-first ordering
  only when `Flipper.enabled?(:featured_listings)`. `with_card_includes` eager loads
  store/photos/labels/tags.
- Routes: `resources :listings, only: %i[index show]`, `resources :categories, only: :show,
  path: "c"`, `resources :stores, only: :show`, `get "search" → listings#index`
  (renders, never redirects — asserted by a test).
- Controllers stay skinny: `ListingsController#index` builds `@result` (also used by
  `CategoriesController#show`, which merges the category slug into the params, and by
  `StoresController#show`, which merges `seller:`); `#show` uses `fresh_when(etag:,
  last_modified:, public: true)` and queues `ListingViewJob` for non-owner, non-bot hits.
  Visibility: approved/sold/reserved public; draft/pending_review/rejected/archived only
  for owner or admin (404 otherwise). Sold listings render a sold banner and no buy CTAs.
- Browse UI: `listings/_browse` wraps one `<form method="get" data-turbo-frame="results">`
  around `_filters` (sidebar + mobile `<dialog>` sheet) and `<turbo-frame id="results"
  data-turbo-action="advance">`, so filtering swaps only the results. `shared/_listing_card`
  is a locale-keyed cached fragment; `shared/_card_rail` powers the home rails and the
  "similar listings" block. Listing show: gallery carousel, specs table, shipping/estimate,
  store card, breadcrumb. Store page: `?tab=listings|about|reviews`.
- Header mega menu (desktop hover/focus panels + mobile `<details>` accordions), cached
  per locale and busted by `Category.maximum(:updated_at)`; tap targets are `min-h-11`
  (44px) across header, filters and sort controls, and the browse grid stacks to one
  column on small screens. New Stimulus controllers: `mega_menu`, `filters`, `gallery`
  (plus the existing `menu`, `theme`).
- Home sections (`pages/home/*`): hero, category tiles, deals, newest, GPU rail, saved/
  popular, recently sold, trust, newsletter.
- Helpers (`ListingsHelper`): `money` (locale-formatted, always shows cents except for
  round EUR where the currency style allows), `spec_value_label`, `stars` (clamped SVG
  rating), facet option builders with counts, applied-filter chips, breadcrumbs,
  `photo_variant_tag`/`listing_photo_tag` (webp `card` 400 / `gallery` 1200, always
  `loading="lazy" decoding="async"` + width/height, SVG placeholder otherwise).
- i18n: 481 identical keys in all six locales, `script/lint_locale_keys.rb` green, British
  English in `en`. Plurals are nested maps (`count: { one:, other: }`).
- Dev sample catalogue: `db/seeds/sample_listings.rb` (dev-only, idempotent) — 5 sellers,
  41 listings, 13 reviews, 80 generated placeholder photos.

**Why**

Public browsing is the whole SEO/traffic surface, so the phase is organised around the
query layer (one service, one facet query, eager loading, fragment caching, conditional
GETs) with deliberately thin controllers, and every interactive control is a plain GET
form that degrades without JS (Turbo Frame is progressive enhancement).

**Gotchas recorded**

- pagy 43.8 ships no railtie: `include Pagy::Method` in `ApplicationController`,
  `Pagy::Offset.new(...)` inside the service, `Pagy::I18n.locale = I18n.locale.to_s` in
  `switch_locale`, nav via `raw(pagy.series_nav)`; do **not** add `pagy.*` keys to the app
  locale files.
- `trg_listings_tsv` only fires on `UPDATE OF title, description`, so fixture INSERTs
  leave `tsv` null → global `setup { Listing.reindex_search_vectors! }` in
  `test/test_helper.rb`.
- `Authentication` must run `resume_session` **before** the auth filters, otherwise
  public controllers (`allow_unauthenticated_access`) never set `Current.user` and
  per-user fragments/CTAs render as logged-out for signed-in users.
- `Store.friendly.find` (not `find!`) — FriendlyId scoped by `slug`.
- Raw Ruby such as `aria: { label: … }` must not be written inside literal HTML tags in
  ERB; use `aria-label="<%= … %>"` there and keep the hash form for tag helpers.
- Fixture slugs must not collide with dev seed slugs
  (`ReferenceDataSeedTest` asserts exact reference counts: 61 categories, 34 spec
  attributes, 293 options, 88 attachments, 13 labels, 21 seller tags).
- Dev uses `:memory_store`, so cached fragments (mega menu, cards, rails) survive template
  and locale edits while the server runs. Restart the server or `Rails.cache.clear` before
  judging a smoke test.

**Files touched** (all uncommitted, on top of `e145877`)

- New: `app/controllers/{listings,categories,stores}_controller.rb`,
  `app/services/listing_search.rb`, `app/jobs/listing_view_job.rb`,
  `app/helpers/listings_helper.rb`, `app/javascript/controllers/{mega_menu,filters,gallery}_controller.js`,
  `app/views/listings/*`, `app/views/shared/{_listing_card,_card_rail}.html.erb`,
  `app/views/stores/show.html.erb`, `app/views/pages/home/*`, `db/seeds/sample_listings.rb`,
  `test/services/listing_search_test.rb`, `test/controllers/{listings,categories,stores}_controller_test.rb`,
  `test/helpers/listings_helper_test.rb`, `test/fixtures/{labels,listing_labels,seller_tags,listing_tags}.yml`.
- Modified: `config/routes.rb`, `config/locales/{es,en,fr,de,it,pt}.yml`,
  `app/controllers/{application,concerns/authentication}.rb`,
  `app/models/{listing,category,spec_attribute,review}.rb`, `app/helpers/application_helper.rb`,
  `app/views/layouts/_header.html.erb`, `app/views/pages/home.html.erb`,
  `app/assets/tailwind/application.css`, `db/seeds.rb`, `test/test_helper.rb`,
  `test/models/listing_test.rb`, `test/fixtures/{listings,categories,category_spec_attributes,spec_attributes,spec_options}.yml`,
  `.claude/context/*`.

**Verification** `bin/rails test` → 133 runs / 851 assertions / 0 failures / 0 errors;
`bin/rubocop` → 138 files, 0 offences; `ruby script/lint_locale_keys.rb` → "All 6 locale
files share the same 481 keys"; `bin/rails db:seed` twice → 0 new records;
`bin/rails tailwindcss:build` OK; smoke curl on `/es`, `/es/c/gpus`, `/en/listings?q=rtx`,
`/en/search?q=rtx` (200, not a redirect), a listing show (200 + 304 on `If-None-Match`),
a filtered category page and `/es/stores/<slug>?tab=reviews` — all 200, zero
"translation missing", 0 errors in `log/development.log`.

## 2026-11-17 — Phase 2a: reference-data seeds (taxonomy, spec filters, labels, seller tags)

**What was built**

- Idempotent seed loaders: `db/seeds.rb` loads `db/seeds/support/seed_loader.rb`
  (module `SeedLoader`: YAML reader with `aliases: true`, 6-locale map validator,
  `display`-fallback for non-translatable labels) then, in order,
  `countries_settings.rb` (delegates to `Country.seed_defaults!` /
  `Setting.seed_defaults!`), `categories.rb`, `spec_attributes.rb` (attributes +
  options + `CategorySpecAttribute` attachments incl. `required` flags),
  `labels_seller_tags.rb`. Every loader upserts by slug/key/value
  (`find_or_initialize_by` + `update!`); loaders are `load`ed (not required)
  so repeated `db:seed` runs re-execute — verified idempotent (two dev runs,
  counts unchanged).
- Raw admin-readable data in `db/seeds/data/`: `categories.yml` (10 roots with
  icon + 6-locale seo_description, 51 children = 61 categories),
  `spec_attributes.yml` (34 attributes, 293 options, `x-shared` YAML anchors
  for the recurring "Other"/"None" maps; `popular` per spec; brand/standard
  labels use one `display` string across locales — proper nouns — capacity
  names are real translations incl. FR "Go/To"), `category_spec_attributes.yml`
  (88 attachments; gpu_chipset required for gpus, cpu_brand for cpus; roots
  like gaming-pcs/workstations inherit down), `labels.yml` (13 labels + hex
  colours), `seller_tags.yml` (21 tags). All names carry es/en/fr/de/it/pt.
- Test `test/seeds/reference_data_test.rb`: runs `db/seeds.rb` twice inside the
  test transaction, asserts identical counts + exact per-table created counts
  (61/34/293/88/13/21/countries+4/settings+4), 6-locale coverage for every
  seeded Category/SpecAttribute/SpecOption/Label/SellerTag, root icons +
  seo_descriptions, `gpus.all_spec_attributes` includes gpu_chipset (+ child
  inheritance, required flags, popular-option sets).

**Why**

Phase 2a per the roadmap: reference data must be admin-editable (YAML, one
file per concern), re-seedable without duplicates, and complete in all six
locales. Gotchas recorded: `YAML.load_file` needs `aliases: true`; re-`load`ing
a file that defines constants emits "already initialized" warnings, so the
constant-holding helper is `require`d while data loaders are `load`ed. Dev DB
contains two pre-seed smoke rows (`categories/rtx`, `gpu_memory:12gb` option)
left over from earlier manual testing — harmless, not duplicated by seeds.

**Files touched**: db/seeds.rb; db/seeds/{support/seed_loader,countries_settings,categories,spec_attributes,labels_seller_tags}.rb;
db/seeds/data/{categories,spec_attributes,category_spec_attributes,labels,seller_tags}.yml;
test/seeds/reference_data_test.rb.

## 2026-11-17 — Phase 1: domain layer (full model layer, associations, I18n)

**What was built**

- Complete domain model layer (no controllers/views yet): 33 new migrations
  (`db/migrate/20261117090001`–`20261117090033`), 25 new models + `Money` value
  object + `CommissionCalculator` service; `User` extended (associations,
  `display_name`, `banned?/ban!/unban!`). Full I18n model/attribute/enum trees in
  all 6 locale files (330 shared keys, lint green). Tests: 66 runs / 180
  assertions green; rubocop clean.
- **Schema format switched to :sql** (`schema_format: sql` in `config/database.yml`,
  `db/structure.sql` replaces `db/schema.rb`) — the Ruby schema dumper drops
  triggers, so `db:test:prepare` was silently losing the listings tsvector trigger.

**Key decisions**

- Migrations only, never hand-edit `db/structure.sql`; every migration reversible
  (`db:migrate VERSION=0` + redo exercised in dev).
- Search: `listings.tsv` tsvector column + trigger (`listings_tsv_trigger` /
  `trg_listings_tsv`, `simple` config, title weight A, description B) + GIN index;
  `Listing.search_text` via pg_search (`tsearch: { tsvector_column: "tsv", dictionary: "simple" }`).
- Slugs: FriendlyId on Listing/Category/Store (`:slugged`, Listing also
  `:sequentially_slugged` with `slug_candidates [:title, [:title, :id]]`).
- Order numbers: Postgres sequence `order_number_seq` created in the orders
  migration (dropped in `down`); format `PCM-YYYY-NNNNNN`, assigned in
  `Order#assign_number` when blank.
- Money: integer-cent columns everywhere + `Money` value object
  (`app/models/money.rb`: `cents`, `currency`, `amount` BigDecimal, `to_s`);
  `Listing#price` returns `Money.new(price_cents, currency)`; orders keep
  subtotal/shipping/commission/total cents and `before_validation :recalculate_total`.
- `Listing` state machine (statuses: draft, pending_review, approved, rejected,
  sold, archived, reserved): `submit_for_review!`, `approve!(admin)` (records a
  `ModerationEvent`), `reject!(reason, admin:)`, `mark_sold!`; invalid transitions raise
  `Listing::InvalidTransition` with `t("listings.transition.*")` messages.
- Enums are plain integer columns; `listing.status` returns a String — the state
  machine compares `from.map(&:to_s).include?(status.to_s)`.
- `Setting.get/set` caches `settings/<key>` (nil-safe: missing keys fall through
  to the default), invalidated by `after_commit :clear_cache` plus a synchronous
  `clear_cache` call inside `Setting.set` (public method; after_commit does not
  fire inside transactional tests).
- Counter caches: `listings.favorites_count` (Favorite `counter_cache:`),
  `stores.listings_count` (Listing belongs_to), `stores.reviews_count/rating_average`
  via `Store#refresh_rating!` from Review after_create/after_destroy/after_update.
- API tokens: `ApiToken.issue_for(user, name:, expires_at:)` returns the clear
  token once, stores `Digest::SHA256.hexdigest` (`token_digest`, unique index);
  `ApiToken.authenticate(raw)` finds an *active* (unexpired) token, touches
  `last_used_at`, returns nil otherwise.
- Category hierarchy via recursive CTEs (`Category#self_and_descendant_ids`
  public, `#self_and_ancestor_ids` private); `all_spec_attributes` merges own +
  inherited spec attributes (own joins win). Names are JSONB locale maps
  (`names: {en:…, es:…}`), `name` falls back to en.
- Photos: ActiveStorage `has_many_attached :photos` on Listing; count (12),
  content types (jpeg/png/webp) and size (10 MB) validated in the model because
  attach persists immediately (custom error keys
  `activerecord.errors.messages.photo_*`).
- `SpecAttribute` input_type enum uses `prefix: true` (bare `select`/`number`
  collide with AR methods).

**Gotchas / follow-ups**

- Fixtures load under PG `disable_referential_integrity` (`DISABLE TRIGGER ALL`),
  so the tsv trigger never sees fixture rows — `ListingTest#setup` re-runs the
  reindex UPDATE. Any trigger-dependent fixture data needs the same treatment.
- Test DB must be prepared with `bin/rails db:test:prepare` **now that structure.sql
  is the dump format** (pg_dump keeps the trigger). If a worker DB predates the
  switch, drop the `app_test_three_test_*` databases.
- Model unit tests run with `I18n.default_locale = :en` (set in
  `test/test_helper.rb`) so English error-message assertions work; locale-specific
  tests wrap in `I18n.with_locale(:es)`.
- Fixtures for JSONB columns must be plain YAML hashes (a JSON *string* fixture
  value gets double-encoded and the model reads back a String).
- `Country.seed_defaults!` is idempotent (`find_or_initialize_by` + `update!`);
  only ES enabled. `Setting.seed_defaults!` uses `set` unless exists.
- Flipper `disable` on never-seen features logs a harmless warning.
- No pg_search typo tolerance yet (dmetaphone deferred); Pagy not wired yet;
  dev DB currently contains smoke-test seed data.

## 2026-11-16 — Phase 0: foundation (brand PCMarket, gems, auth, i18n, chrome)

**What changed**

- Gems added: tailwindcss-rails, bcrypt, pagy, friendly_id, pg_search, flipper,
  flipper-active_record, meta-tags, sitemap_generator, rack-attack, rails-i18n, stripe,
  faker (default group). Ran `tailwindcss:install`, `rails g authentication`,
  `g flipper:active_record`.
- Migrations: `create_users`, `create_sessions` (generator), `create_flipper_tables`,
  `add_profile_fields_to_users` (username unique/not null, first/last name, phone,
  role enum default 0, locale "es", country_code "ES", confirmed_at).
- `User`: username/email validations, downcase normalization, role enum, locale inclusion.
- Sign-up: `RegistrationsController` as RESTful `resource :registration` (new/create),
  auto sign-in after registration, rate limited.
- I18n: locales es/en/fr/de/it/pt (default :es, fallbacks :en); all routes wrapped in
  `scope "(:locale)"`; `ApplicationController#switch_locale` + locale
  `default_url_options`; 6 locale files with identical key trees (checker:
  `script/lint_locale_keys.rb`); every phase-0 string, including auth flashes and the
  password-reset mailer, goes through I18n.
- Layout: Tailwind chrome with header (announcement bar, PCMarket logo, search form,
  "List an item"/"Sell to us" placeholders, wishlist/notifications/cart/account icons,
  account dropdown or Log in), footer (newsletter, About/Help/Buying & selling columns,
  language switcher, copyright), flashes partial, meta-tags, `<html lang>`.
- Design tokens + dark mode: CSS variables in `app/assets/tailwind/application.css`,
  Tailwind v4 `dark` custom variant, `theme_controller.js` (localStorage try/catch +
  prefers-color-scheme), `menu_controller.js` (slide-in menu < md).
- `PagesController#home` hero placeholder behind root route.
- Rack::Attack and Flipper initializers.
- Tests: `user_test.rb` (valid user, email normalization, username format/uniqueness),
  `pages_controller_test.rb` (/es, /en, locale-less root). `test/test_helper.rb` pins
  integration-test URL locale to :en (fixes both the generated English flash assertions
  and positional-arg binding under `(:locale)`).

**Why**

Establish the base every later phase (listings, checkout, admin) builds on, per the
Phase 0 spec. Notable gotcha recorded: with routes under `(:locale)`, positional route
helpers (`password_path(token)`) bind positionally to path segments — the URL options
must carry `:locale`, hence `routes.default_url_options` in tests and
`default_url_options` in `ApplicationController`.

**Files touched**: Gemfile/Gemfile.lock; config/{application.rb,routes.rb};
config/initializers/{flipper,rack_attack}.rb; config/locales/{es,en,fr,de,it,pt}.yml;
db/migrate/2026111620530{1,2,3}*.rb, 20261116205400*.rb; app/models/user.rb;
app/controllers/* (application, sessions, passwords, registrations, pages) +
concerns/authentication.rb; app/mailers/passwords_mailer.rb;
app/views/{layouts/*,pages/home*,sessions/new*,passwords/*,registrations/new*,passwords_mailer/*};
app/helpers/application_helper.rb; app/assets/tailwind/application.css;
app/javascript/controllers/{theme,menu}_controller.js;
test/{test_helper.rb,fixtures/users.yml,models/user_test.rb,controllers/pages_controller_test.rb};
script/lint_locale_keys.rb.
