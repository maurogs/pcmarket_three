# History

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
