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

## Code map

| Area | Files |
| --- | --- |
| Routes (locale-scoped) | `config/routes.rb` — root `pages#home`, `resource :session`, `resources :passwords`, `resource :registration` |
| Auth | `app/controllers/concerns/authentication.rb` (cookie resume, `Current.session`), `sessions_controller.rb`, `passwords_controller.rb`, `passwords_mailer.rb` |
| Sign-up | `registrations_controller.rb` + `views/registrations/new` |
| User model | `app/models/user.rb` — `email_address` (normalized downcase, uniq index), `username` (uniq index, `/\A[a-zA-Z0-9_\-]{3,30}\z/`), `first_name`, `last_name`, `phone`, `role` enum (user:0 admin:1), `locale` (default "es"), `country_code` (default "ES"), `confirmed_at` |
| Locale switching | `application_controller.rb`, `config/application.rb`, `config/locales/*.yml`, `script/lint_locale_keys.rb` |
| Layout & chrome | `app/views/layouts/application.html.erb`, `_header.html.erb` (announcement, logo, search `GET /:locale?q=`, placeholders, icons, account dropdown, hamburger menu), `_footer.html.erb` (newsletter, link columns, language switcher, copyright), `_flashes.html.erb` |
| Design tokens | `app/assets/tailwind/application.css` (`--color-primary` #4f46e5, `--color-accent` #f97316, surface/surface-muted/text/muted/border; `.dark` overrides) |
| Stimulus | `app/javascript/controllers/theme_controller.js`, `menu_controller.js` |
| Migrations | `db/migrate/20261116205301_create_users.rb`, `...205302_create_sessions.rb`, `...205303_create_flipper_tables.rb`, `...205400_add_profile_fields_to_users.rb` |
| Tests | `test/models/user_test.rb`, `test/controllers/pages_controller_test.rb`, generated `sessions`/`passwords` controller tests, `test/test_helpers/session_test_helper.rb` (`sign_in_as`) |

## Open items (next phases)

- Listings resource (FriendlyId slugs, pg_search, Flipper `featured_listings`), admin approval flow.
- Cart/checkout (Stripe, flag `stripe_checkout`), "Sell to us" (flag `sell_to_us`), commissions (flag `commissions`).
- Google login (flag `google_login`), email confirmation (`confirmed_at` exists but is unused).
- `/api/v1` namespace, sitemap_generator config, meta-tags per-page SEO, Pagy wiring.
- Add `script/lint_locale_keys.rb` to CI.
