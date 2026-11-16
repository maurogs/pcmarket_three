# PCMarket — Project Context

## Purpose

Marketplace for new and second-hand PC hardware (GPUs, CPUs, laptops, components).
Phase 0 built the foundation: auth, i18n, Tailwind chrome (header/footer), and the
decision record below. Listings, search, checkout and admin come in later phases.

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

## Code map

| Area | Files |
| --- | --- |
| Routes (locale-scoped) | `config/routes.rb` — root `pages#home`, `resource :session`, `resources :passwords`, `resource :registration` |
| Auth | `app/controllers/concerns/authentication.rb` (cookie resume, `Current.session`), `sessions_controller.rb`, `passwords_controller.rb`, `passwords_mailer.rb` |
| Sign-up | `registrations_controller.rb` + `views/registrations/new` |
| User model | `app/models/user.rb` — `email_address` (normalized downcase, uniq index), `username` (uniq index, `/\A[a-zA-Z0-9_\-]{3,30}\z/`), `first_name`, `last_name`, `phone`, `role` enum (user:0 admin:1), `locale` (default "es"), `country_code` (default "ES"), `confirmed_at`, `banned_at` (`banned?/ban!/unban!`), `display_name`; has_many: store, listings, sales/orders, favorites, follows, seller_follows, saved_searches, conversations, offers, carts, reviews, sent_messages, api_tokens |
| Locale switching | `application_controller.rb`, `config/application.rb`, `config/locales/*.yml`, `script/lint_locale_keys.rb` |
| Layout & chrome | `app/views/layouts/application.html.erb`, `_header.html.erb` (announcement, logo, search `GET /:locale?q=`, placeholders, icons, account dropdown, hamburger menu), `_footer.html.erb` (newsletter, link columns, language switcher, copyright), `_flashes.html.erb` |
| Design tokens | `app/assets/tailwind/application.css` (`--color-primary` #4f46e5, `--color-accent` #f97316, surface/surface-muted/text/muted/border; `.dark` overrides) |
| Stimulus | `app/javascript/controllers/theme_controller.js`, `menu_controller.js` |
| Taxonomy | `category.rb` (self-referential `parent_id`, JSONB `names` locale maps, recursive CTEs `self_and_descendant_ids`/`self_and_ancestor_ids`, FriendlyId; NOTE `categories.listings_count` is a plain counter_cache of ALL listings including drafts/rejected — public per-category counts must query `Listing.published`/`visible`), `spec_attribute.rb` (`key`, JSONB names, `input_type` enum with `prefix: true`) + `spec_option.rb` + join `category_spec_attribute.rb` — spec attributes attach to any category and are inherited down the tree (`Category#all_spec_attributes`) |
| Listings | `listing.rb` — FriendlyId `:slugged, :sequentially_slugged` (`slug_candidates`), pg_search `search_text` (tsvector column `tsv` + trigger + GIN in migrations 090008/090009), enums `condition` (brand_new/open_box/used_like_new/used_good/for_parts) and `status` (draft/pending_review/approved/rejected/sold/archived/reserved) with transitions `submit_for_review!`/`approve!(admin)`/`reject!(reason, admin:)`/`mark_sold!` raising `Listing::InvalidTransition`; integer-cent columns (`price_cents` etc.) + `Money` value object (`Listing#price`, `discount_percent`); JSONB `specs` (may be empty — accessories/games have none — but must be a Hash); photos via ActiveStorage (`has_many_attached`, 12/10 MB/jpeg-png-webp model validations); scopes: `published/visible/featured/in_country/recent`; labels/tags: `label.rb`, `listing_label.rb`, `seller_tag.rb`, `listing_tag.rb`, moderation: `moderation_event.rb` |
| Stores & reputation | `store.rb` (FriendlyId, counters `listings_count/reviews_count/rating_average`, `refresh_rating!`), `review.rb` (uniq `order_id`, reviewer/store/seller), `favorite.rb` (counter cache on `favorites_count`), `follow.rb` |
| Commerce | `cart.rb`, `cart_item.rb`, `order.rb` (number `PCM-YYYY-NNNNNN` from `order_number_seq`, integer-cent totals + `recalculate_total`, `apply_commission!` gated by Flipper `:commissions` + `Setting commission_percent`), `order_item.rb`, `address.rb`, `offer.rb`, `app/services/commission_calculator.rb` |
| Messaging | `conversation.rb`, `message.rb`, `block.rb` |
| Platform | `country.rb` (JSONB-free locale rows via `name_key` i18n keys, `Country.seed_defaults!` ES-only), `setting.rb` (`get/set` + Rails.cache key `settings/<key>`, `seed_defaults!`), `api_token.rb` (`issue_for` → SHA-256 `token_digest`, `authenticate` active-only), `legal_page.rb`, `newsletter_subscription.rb`, `notification.rb`, `saved_search.rb`, `money.rb` (value object: `cents`/`amount`/`to_s`) |
| Migrations | Phase 0: `20261116205301…205400`. Phase 1 domain: `db/migrate/20261117090001`–`20261117090033` (countries, settings, stores, categories, spec_*, listings + tsv trigger/GIN, labels/tags/moderation, favorites/follows, saved_searches, conversations/messages/blocks, offers, carts/cart_items, addresses/orders/order_items, reviews, notifications, newsletter, legal_pages, api_tokens, user ban fields, active_storage). Schema dump: `db/structure.sql` (schema_format: sql in `config/database.yml`) |
| Tests | `test/models/user_test.rb`, `test/models/{listing,category,setting,country,api_token,review,favorite}_test.rb`, `test/services/commission_calculator_test.rb`, `test/controllers/pages_controller_test.rb`, generated `sessions`/`passwords` controller tests, `test/test_helpers/session_test_helper.rb` (`sign_in_as`); fixtures for users/countries/categories/spec_*/stores/listings/orders. `test_helper.rb`: `I18n.default_locale = :en` for error-message assertions; `ListingTest` re-runs the tsv reindex in setup (fixtures load with triggers disabled) |

## Open items (next phases)

- Listings UI phase: CRUD + publish flow (admin approval per `Listing` state machine), search page wired to `Listing.search_text` + Pagy, photo upload form (validations live in the model).
- Cart/checkout (Stripe, flag `stripe_checkout`), "Sell to us" (flag `sell_to_us`), commissions (flag `commissions`, `CommissionCalculator` + `Order#apply_commission!` ready).
- Google login (flag `google_login`), email confirmation (`confirmed_at` exists but is unused).
- `/api/v1` namespace (`ApiToken.authenticate` ready), sitemap_generator config, meta-tags per-page SEO.
- Seed data: `Country.seed_defaults!` + taxonomy seeds into `db/seeds.rb`; pg_search typo tolerance (dmetaphone) if needed.
- Add `script/lint_locale_keys.rb` to CI.
