# History

## 2026-11-18 — Phase 6b: admin panel part 2 — orders/disputes/refunds, review moderation, taxonomy, countries, feature flags, settings, legal pages, audit log browse

**What changed**

- Migrations: `20261118015001` (`order_notes`: order FK, admin FK, body),
  `20261118015002` (orders `refund_cents`), `20261118015003`
  (reviews `hidden_at` — moderation hides, row kept).
- **Orders**: `Admin::OrdersController` (index with filters via
  `Admin::OrderFilter` + search, show with timeline/notes, `update` = audited
  FORCED status transition with reason — admins bypass the buyer/seller
  guards) and nested `Admin::NotesController` (create/destroy internal notes).
- **Disputes**: `Admin::DisputesController` (disputed orders first workspace)
  + nested `resource :resolution` → `Admin::ResolutionsController` (new/create)
  driving `Disputes::Resolve` service: refund (Stripe charge refund through
  `Payments::StripeRefund` when the order has a `payment_reference`, else
  direct mark) or release-to-seller; order → `refunded` state stamping
  `refund_cents` (no listing restock — the buyer kept the goods) or
  `disputed → completed` for the seller, Notification to buyer + seller +
  `OrderMailer#refund_issued`/`#dispute_resolved`. `Order` gained `refund!`/
  `release_to_seller!` transitions; admin forced transitions go through
  `Orders::ForceTransition` (reason + notify required).
- **Review moderation**: `Admin::ReviewsController#index` (state/rating/store
  filters) + `destroy` = hide with a REQUIRED reason (blank → alert, nothing
  happens); `Review#hide!/unhide!/hidden?` + `visible/hidden` scopes; store
  rating recomputed by the existing `after_update` callback.
- **Taxonomy**: `Admin::CategoriesController` (tree index, create/edit with
  translated `names` + `seo_descriptions` tabs, archive via `active`), nested
  `Admin::PositionsController` (up/down → `Category#move!`),
  `Admin::CategorySpecAttributesController` (attach/update/detach spec attrs
  per category). `Admin::SpecAttributesController` (CRUD except show; `key`
  is immutable after create — update filters it out, model error key
  `:immutable`), nested `Admin::SpecOptionsController` +
  `Admin::SpecOptionMergesController` (merge rewrites every referencing
  `listings.specs` entry with ONE UPDATE; delete blocked while in use) +
  `Admin::BulkOptionsController` (one option per textarea line). `Label`s and
  `SellerTag`s CRUD with translated names.
- **Platform**: `Admin::CountriesController` (edit currency/locale/VAT +
  enable toggle; `Country` validation blocks enabling while legal pages are
  missing — `missing_legal_slugs` vs `LegalPage::SLUGS` (6 slugs) published
  in the country's default locale; error `activerecord.errors.messages.missing_legal_pages`
  interpolates `%{slugs}`). `Admin::FeatureFlagsController` — registry
  `FeatureFlags::FEATURES` in `config/initializers/flipper.rb` (5 flags,
  `description_key` + optional `warning`), `FeatureFlags.warning_for`
  (soft, never blocks: `stripe_checkout` warns while STRIPE env keys missing,
  `commissions` warns while `commission_percent` is 0) and
  `FeatureFlags.register_all!` (idempotent `Flipper.add`).
  `Admin::SettingsController` (singular resource) → `Admin::Settings::Update`
  validates EVERY field before touching any Setting row (commission_percent
  0..20 etc., e-mail format, integers; errors keyed
  `admin.settings.edit.errors.{out_of_range,invalid_email,invalid_number}`,
  422 re-render showing what was typed; one `settings_update` audit row).
  `maintenance_mode` → `ApplicationController#enforce_maintenance_mode`
  renders `application/maintenance` 503 for public pages; the Admin module +
  signed-in admins bypass. `Admin::LegalPagesController` CRUD (markdown body
  via `LegalPagesHelper#render_legal_page_body`).
  `Admin::NewsletterSubscriptionsController` (index + CSV via the generic
  `CsvBuilder` service + destroy). `Admin::AuditLogsController#index`
  (read-only browse, action/subject filters).
- `TranslatableJsonb` concern gained `assign_translations(attr, hashes)` —
  the controller-written pattern for JSONB locale maps (`permit(names: {})`
  + per-locale merge, untouched tabs survive).
- Tests: `access_test.rb` now sweeps EVERY admin GET route (30 new 6b
  entries) and 6b write routes with state-not-changed assertions; new
  `test/controllers/admin/{countries,feature_flags,settings}_controller_test.rb`;
  page_render/disputes/orders/reviews/categories/spec_*/labels/seller_tags/
  legal_pages/audit_logs/csv tests from the build itself. Admin dir: 203 runs.

**Gotchas learned**

- Strong params gotcha: `permit(foo: {})` (unrestricted hash for translations)
  keeps `Parameters`; passing raw params to services raises
  `UnfilteredParameters` at `.to_h`. The `names: {}` permit is what makes
  `assign_translations` work.
- Flipper 1.4 has NO `Flipper.disabled?` module method (use
  `!Flipper.enabled?`); a percentage gate's `Feature#state` is `"conditional"`.
- **Rails.cache is not transactional** — a `Setting.set` in one test survives
  the rollback inside the cache (maintenance_mode stayed true for the whole
  next test in the worker → public 503s everywhere). `test_helper.rb` now has
  a global `setup { Rails.cache.clear }`.
- Category fixture `rtx` has slug `rtx-series` — `Category.friendly.find`
  needs the slug, not the fixture key.
- `Category#move!` needs explicit bounds (`target.negative? || target >=
  siblings.size`) — negative offsets used to wrap to the end.
- `assert_not_match` does not exist; the alias is `assert_no_match`.
  Ruby 4 forbids bare `super` inside `define_method` blocks
  (`super(*args, **kwargs)`).
- Commonmarker 2.10 injects empty `<a class="anchor">` self-anchors per
  heading with no disable option — `LegalPagesHelper` strips them before
  sanitize.
- Fixture order numbers are `PCM-2025-*` (sequence collision, see Phase 4b note).

**Verification** — `bin/rails test` 655 runs / 3702 assertions / 0F 0E;
`bin/rubocop` clean (377 files); locale linter green (6 files × 1980 keys);
`tailwindcss:build` OK; `Rails.application.eager_load!` OK. Not committed.

## 2026-11-18 — Phase 6a: admin panel part 1 — moderation queue, listings, users (ban/impersonation), stores, dashboard, audit log

**What changed**

- Routes: `namespace :admin` inside the locale scope (no `as:` on root —
  `admin_root` comes from the namespace). All controllers inherit
  `Admin::BaseController` (`layout "admin"` + `require_admin!`): **non-admins
  get 404, never 403** (existence is a leak); banned admins get the sign-in
  page with an alert instead.
- **Audit trail**: `AdminAuditLog` (append-only: admin, polymorphic subject,
  action, details jsonb; migration `20261118010002`) written through the
  `Admin::Auditable` concern (`audit!(action, subject, **details)`). Bulk
  moderation logs ONE `bulk_approve`/`bulk_reject` row per batch.
- **Migration `20261118010001`**: `pg_trgm` extension + GIN index on
  `listings.title` (`Listing.potential_duplicates_of` — duplicate hints on
  the moderation cockpit).
- **Moderation**: `Admin::ModerationsController` (queue oldest-first,
  cockpit show with seller card + pg_trgm duplicate hints),
  `Moderations::{Approve,Reject}` services (status transition + Notification
  + `ModerationMailer` deliver_later + ModerationEvent), `RejectionsController`
  (form with fixed `REASONS` keys, labels under `admin.rejections.reasons.*`,
  unknown/blank reason → 422 re-render), `Admin::BulkModerationsController`
  (≤50 ids, per-listing events + one aggregate audit row).
- **Listings admin**: index with status/country filters (`Admin::ListingFilter`),
  CSV export (`Listings::CsvExport` — builds a String, headers + rows),
  edit via `Listings::AdminUpdate` (status changes recorded as moderation
  events, unpublish event when pulled down), `UnpublicationsController`
  (approved→archived), destroy only for draft/rejected/archived
  (`destroy_denied` flash otherwise), global search (`Admin::GlobalSearch`
  across listings/users/orders).
- **Users admin**: index + user page (listings, store, moderation trail),
  role edits through `Users::AdminUpdate` — guards return error-key symbols
  (`:last_admin` checked BEFORE `:cannot_demote_self`) and the save is SKIPPED
  when blocked (a `save` would clear manually-added errors).
  `Users::Ban` (ban! + destroy sessions/api_tokens + archive approved
  listings) / `Users::Unban`. Login itself rejects banned users
  (`sessions/create.banned` alert).
- **Impersonation**: `Admin::ImpersonationsController#create` refuses
  admins/self/deleted, stores `session[:impersonator_id]`, then
  `start_new_session_for(target)`; the sticky red banner
  (`shared/_impersonation_banner`) posts DELETE `destroy`, which SKIPS
  `require_admin!` (Current.user is the target then) and re-authenticates
  the impersonator after validating the stored id. While impersonating, all
  admin routes 404 (Current.user is the non-admin target).
- **Stores admin**: index (verified filter, hidden still listed),
  verify/unverify + hide/unhide controllers (`admin_store_verification_path`
  / `admin_store_hiding_path` POST/DELETE), edit name/slug bits.
- **Dashboard**: `Admin::DashboardStats.call` → `Result` struct (counts,
  pending queue, approval rate + daily series from ModerationEvents,
  `oldest_pending_listings`/`latest_signups` as CLASS methods, latest audit
  activity).
- **i18n follow-up (big one)**: every enum whose label is rendered via
  `Model.human_attribute_name` now uses FLATTENED slash keys in all 6
  locales — `attributes.listing: { "status/draft": Draft, … , status: Status }`
  (same for `listing/condition`, `user/role`, `moderation_event/action`,
  `offer.status`, `order.status`). The old nested `{status: {draft: …}}`
  shape NEVER resolved through `human_attribute_name("status/draft")` and
  crashed plain `"status"` lookups with "can not be used with :count => 1"
  (hash + pluralization). Locale tree is now **1496 keys**.
- **Tests**: `test/controllers/admin/{access,listings,moderations,stores,users}_test.rb`
  (access = 404 sweep over EVERY admin GET + write routes incl. bulk,
  impersonation, updates, state-not-changed assertions) +
  `test/services/admin/dashboard_stats_test.rb`. Suite: **471 runs, green**;
  rubocop / locale lint / tailwind build / eager-load all pass.

**Gotchas learned**

- `human_attribute_name("status/draft")` resolves ONLY when the YAML has a
  literal quoted key `"status/draft"` under `attributes.<model>`; dots in the
  argument mean YAML NAMESPACE, slash keys are literal.
- `Category` has NO `name` column (JSONB `names`) — never `order(:name)`;
  use `Category.ordered` / `roots.active.ordered`.
- Only `date.formats.delivery` exists (no `time.formats.*`) — pass `.to_date`
  to `l(..., format: :delivery)`.
- Locale keys must match the CONTROLLER's lexical scope: the impersonation
  node is `admin.impersonation.*` (singular) while the controller is
  `ImpersonationsController`, so its flashes use absolute `t()` keys.
- Flash strings with `%{interpolation}` need the args passed at the call
  site (`t(".destroyed", title:)`, `t(".updated", name:)`) — missing args
  leak `%{...}` into the flash.

## 2026-11-17 — Phase 5: wishlists + price-drop alerts, store follows, saved searches & digest, notification centre, account settings (profile/security/GDPR)

**What changed**

- Migrations `20261117230001–230003`: `favorites.price_cents_at_save`,
  `users.notification_preferences` (jsonb), `stores.hidden` (GDPR marker);
  structure.sql dumped, dev + test applied.
- **Wishlist**: `FavoritesController` (create/destroy turbo streams, idempotent
  `find_or_initialize_by`, price stamped at save), `shared/_favorite_button`,
  header heart badge (`header_favorite_count` in `ApplicationController`),
  `favorites/index` shows the drop % since saving (`Favorite#price_dropped?`).
- **Price-drop alerts**: `Listings::PriceDropNotifier` (24 h cooldown per
  listing, only alerts savers whose `price_cents_at_save` is above the new
  price; Notification always created, e-mail only when the user
  `wants_email?("price_drop")`). Runs **synchronously** from the Listing
  `after_update_commit :alert_price_drop` hook (the
  `Listings::PriceDropNotifierJob` was deleted — the notification must exist
  right after the update and the mail is the only async part).
  `PriceDropMailer` re-checks the preference inside the action (guards
  preference flips between enqueue and send; `@previous_cents` nil-safe in
  both templates).
- **Follows**: `FollowsController` (turbo-stream swap of
  `shared/_follow_button` + `stores/_follower_count`; `Store.visible.friendly.find`
  — hidden stores 404), `Follow` model rejects self-follow; Store page shows
  button + count.
- **Saved searches**: `SavedSearchesController` (save from results page,
  toggle alerts, delete — turbo streams; 25-per-user cap in the model,
  on create). `SavedSearch#new_from_search(user:, name:, search_filters:)`
  accepts permitted Parameters (`to_h.with_indifferent_access`); `attribute
  :email_alerts, default: false` at the model (DB column defaults true for
  legacy rows). `SavedSearches::MatchNewListing` (SQL prefilter on category
  ancestry + price band, then authoritative `ListingSearch.new(..., only_id:)`
  — service **class**, `self.call` → `new(listing).call`) writes one
  `saved_search_match` Notification per matching search; `SavedSearchMatchJob`
  (fired by Listing `after_commit` on approve) e-mails once per user when any
  of their matching searches has `email_alerts` + the user wants the channel,
  then touches `last_notified_at` (watermark). `SavedSearchDigest` +
  `saved_search_digest_job` (recurring `saved_search_digest` hourly in
  `config/recurring.yml`) batch unsent matches per user
  (`Notification.unsent_saved_search_matches` = created after the watermark).
- **Notification centre**: `NotificationsController#index` + `NotificationsReadsController`
  (route is `resource :notifications_read` → Rails infers the PLURALised
  controller name, so the class is `NotificationsReadsController`),
  `NotificationsHelper` renders kind → text/link/icon from the jsonb payload
  (`saved_search_match` payload now carries `saved_search_name`; `new_message`
  uses the counterparty's display name; links resolve listing ids through
  `Listing.find_by` so paths render slugs). Header bell `shared/_notifications_badge`
  (`div#notifications-badge`, count from `Notification.unread_count_for`
  cached per user; live via `turbo_stream_from Current.user, :notifications`
  + broadcast in `Notification#bust_unread_cache_and_broadcast`).
  `Notification` gained `unread?`, `unsent_saved_search_matches` scope,
  cache helpers.
- **Account namespace** (`/account/*`, `Account::BaseController` with
  `layout "account"` + `_account_nav`): `profiles` (name/email/phone/locale —
  redirect honours the new locale), `securities` (current-password confirm;
  `User#current_password` is a virtual attr so the error summary can render
  it), `notification_preferences` (6-channel checkbox matrix →
  `User#update_notification_preferences` writes the FULL matrix, missing
  keys → explicit false; `EMAIL_PREFERENCE_KEYS`/`DEFAULT_EMAIL_PREFERENCES`/
  `wants_email?` — everything defaults ON except newsletter), `data_exports`
  (`Users::DataExportJob` builds the GDPR JSON, attaches it to
  `user.export`, `DataExportMailer#ready` mails a 7-day signed blob link —
  deliberately NOT gated on a channel preference, it's the user's own
  transactional request), `deletions` (`Users::Anonymize`: refuses while any
  order is not completed/cancelled (`OpenOrderError`), renames to
  `deleted-<id>@invalid`/`deleted-<id>`, purges avatar, destroys
  addresses/favorites/saved searches/tokens/sessions/blocks, archives ALL
  non-sold listings incl. drafts, hides the store; `User#deleted?` =
  email ends `@invalid`, `wants_email?` returns false for deleted users).
- **Test gotchas learned**: Rails 8.1 `ActionMailer::MessageDelivery` is a
  lazy delegator — assert `NullMail` on `...action.message`, deliver with
  `.deliver_now`; multipart `mail.body.to_s` is empty — use
  `text_part.body.decoded`; quoted-printable splits long URLs, so never
  assert on `body.encoded` substrings; plain `ActiveSupport::TestCase`
  does NOT clear `ActionMailer::Base.deliveries` between tests — classes
  that count absolute deliveries `setup { ActionMailer::Base.deliveries.clear }`;
  `pluck("payload->>'x'")` needs `Arel.sql(...)` on Rails 8.1. Phase 5 tests
  create records in setup instead of adding new fixture files (no
  favorites/follows/notifications/saved_searches fixtures).
- **Gates**: 428 runs / 2224 assertions / 0F 0E; rubocop clean; locale linter
  6 files × 1130 keys; tailwind build OK. Not committed (per instruction).

**Why** — Phase 5 of the plan: engagement features (wishlist + price-drop
notifier, store follows, saved searches with match fan-out and hourly digest)
plus the notification centre and the account area required before launch
(profile, password change, e-mail channel prefs, GDPR export & erasure).

**Files** — see the Phase 5 rows in `project.md` code map; touched:
`app/controllers/{favorites,follows,saved_searches,notifications,notifications_reads,application}_controller.rb`,
`app/controllers/account/*`, `app/models/{user,listing,store,favorite,follow,saved_search,notification}.rb`,
`app/services/{listings/price_drop_notifier,saved_search_digest,saved_searches/match_new_listing,users/{data_export,data_export_job,anonymize}}.rb`,
`app/jobs/{saved_search_match_job,saved_search_digest_job}.rb`,
`app/mailers/{price_drop,saved_search,data_export}_mailer.rb`,
`app/helpers/{notifications,saved_searches}_helper.rb`, views under
`app/views/{account,favorites,notifications,saved_searches,price_drop_mailer,saved_search_mailer,data_export_mailer,shared}/`,
`config/routes.rb`, `config/recurring.yml`, all 6 locale files, and the
phase 5 test files under `test/{models,services,mailers,integration}/`.

## 2026-11-17 — Phase 4b: cart, checkout & order lifecycle (guest carts, per-seller orders, Stripe/direct payment, state machine) + Phase 4a review fixes

**What changed**

- Phase 4a review fixes first: `Offers::Accept` now re-checks offer staleness
  INSIDE the transaction after locking (second concurrent accept → `:stale`,
  regression test added); `MessagesController` rate-limits via
  `rate_limit to: 30, within: 1.minute, by: -> { Current.user.id }` on the
  default `Rails.cache` store (test env `config.cache_store` changed
  `:null_store` → `:memory_store` so the 429 path is testable; integration
  tests clear the store in setup).
- Migration `20261117223000`: orders gain `paid_at/completed_at/cancelled_at`
  datetimes + `checkout_token` string, indexes on `checkout_token` and
  `status` (`shipped_at`/`delivered_at` existed since Phase 1). structure.sql
  dumped; applied to dev + test.
- Cart: `Cart.for_user/for_token/token`; guest carts keyed by a signed
  permanent `:cart_token` cookie, `Carts::Merge` folds the guest cart into the
  user's cart at login (hooked into `authentication.rb#start_new_session_for`:
  quantities stack capped at stock, non-purchasable items are discarded, guest
  cart destroyed, cookie cleared). `Carts::AddItem` is the single rule
  enforcer (approved, not own listing, not reserved-for-another, seller not on
  vacation, quantity ≤ stock); `CartItem` itself deliberately does NOT
  validate approval so stale items survive and are shown greyed by
  `Carts::Summary`.
- Checkout: `Carts::Summary` groups items per seller, marks `stale` items, and
  computes per-seller shipping (0 for pickup when the seller allows it, 0 when
  subtotal ≥ `Store#free_shipping_threshold_cents`, else max of the items'
  `listing.shipping_price_cents`). `Checkout::PlaceOrders` runs in one
  transaction: `SELECT ... FOR UPDATE` locks on the listings, re-validates
  `purchasable_by?` + stock against the LOCKED rows (a listing sold
  mid-checkout fails the whole call — zero orders), creates one `Order` per
  seller with recomputed totals, applies commission when Flipper `:commissions`
  is on, stamps `checkout_token` for idempotent replay, empties the cart,
  marks listings sold, notifies + e-mails both parties. `CheckoutsController`
  mints `session[:checkout_token]` per `show`; `create` checks the replay
  branch BEFORE the empty-cart guard so a double submit lands on the existing
  orders. Payment mode: Stripe Checkout session when
  `Flipper :stripe_checkout && ENV["STRIPE_SECRET_KEY"]`, otherwise
  `Checkout::DirectPayment` posts a system Message into the seeded
  Conversation and redirects there. `StripeWebhooksController` verifies the
  `Stripe-Signature` header with `Stripe::SignatureVerifier` (secret
  `STRIPE_WEBHOOK_SECRET`) and marks linked orders paid on
  `checkout.session.completed` (order ids read from
  `stripe_session["metadata"]["order_ids"]` — stripe-ruby 21 StripeObject has
  no `dig`).
- Order lifecycle: state machine on `Order` (`pending_payment → paid →
  shipped → delivered → completed`, + `cancelled`/`disputed`; guards raise
  `Order::InvalidTransition`; delivery sets `buyer_protection_until =
  now + Order::BUYER_PROTECTION_WINDOW` (2 days); cancel calls
  `restore_listings!` → `reinstate!`/`add_back_quantity!`).
  `Orders::Transition` service wraps model transition + Notification +
  `OrderMailer`. Routes: buyer actions under `resources :orders` (nested
  `delivery_confirmations#create`, `completion/cancellation/dispute` singular
  resources) scoped to `current_user.orders`; seller fulfilment under
  `sell/sales/:sale_id/{payment_confirmation,shipment,cancellation}` scoped
  to `current_user.sales` — role guards are 404s by scoping (buyer can't ship,
  seller can't confirm delivery/cancel-after-delivery, outsiders 404).
  `AutoCompleteOrdersJob` (recurring `auto_complete_orders` in
  config/recurring.yml): completes delivered orders past buyer protection and
  auto-cancels `pending_payment` older than 72h. Reviews: `ReviewsController`
  new/create gated to `completed` orders, `Review` uniq `order_id` = one
  review per order.
- Views: `carts/show` (per-seller groups, stale rows greyed, shipping rows,
  free-shipping progress hint), `checkouts/show` (address picker, per-seller
  pickup checkboxes, hidden `checkout_token`, Stripe vs direct notice),
  `addresses/{index,new}`, `orders/{index,show,_timeline}`,
  `sell/sales/show` fulfilment actions, `reviews/new`; `OrderMailer` 4 actions
  in recipient locale (`ApplicationMailer` now includes `helper ListingsHelper`
  for `money()`). All strings in the 6 locales (linter: 963 shared keys).
- Tests: 373 runs / 1960 assertions green. New: `test/models/{cart,order}_test.rb`;
  services `carts_{add_item,merge,summary}`, `checkout_{place_orders,direct_payment}`,
  `payments_stripe_checkout` (Stripe stubbed by swapping
  `Stripe::Checkout::Session.create` on the singleton class — minitest 6 has
  no `minitest/mock` — asserting line_items/total/metadata params; PlaceOrders
  concurrency test injects a mid-transaction sold via
  `Listing.singleton_class.define_method(:find)`); `test/jobs/auto_complete_orders_job_test.rb`;
  controllers `carts`, `checkouts` (replay + token refusal + Stripe redirect),
  `orders` (role guards + cancellation restores listings), `stripe_webhooks`
  (hand-built valid HMAC signature accepted, bad/missing rejected),
  `sell/sales_controller_test.rb` (seller transitions + 404 guards);
  fixtures `carts/cart_items/addresses.yml`.
- Fixture churn: `orders.yml` numbers renamed `PCM-2026-*` → `PCM-2025-*`
  (fresh `order_number_seq` nextvals 1,2 collide with same-year PCM-2026
  numbers once tests create their own orders); `sell_dashboard_test.rb`
  assertions follow.

**Why**

Phase 4b spec: cart (guest + user), checkout with one order per seller, both
payment modes behind the Stripe flag, and the full order lifecycle with
role-guarded transitions — while keeping logic out of controllers (models +
service objects) and every string in I18n. Idempotent checkout (token replay)
and the mid-checkout-sold race were spec'd explicitly: row locks + re-check
inside the transaction mirror the Phase 4a accept-race fix pattern.

**Files touched**: db/migrate/20261117223000*.rb, db/structure.sql;
config/{routes.rb,recurring.yml,environments/test.rb}; config/locales/{es,en,fr,de,it,pt}.yml;
app/models/{order,cart,cart_item,address,order_item}.rb;
app/services/carts/{add_item,merge,summary}.rb, app/services/checkout/{place_orders,direct_payment}.rb,
app/services/orders/transition.rb, app/services/payments/{stripe_checkout,handle_webhook}.rb;
app/jobs/auto_complete_orders_job.rb; app/mailers/{application_mailer,order_mailer}.rb;
app/controllers/{carts,cart_items,checkouts,addresses,orders,delivery_confirmations,completions,cancellations,disputes,stripe_webhooks,reviews}_controller.rb,
app/controllers/sell/{sales,payment_confirmations,shipments,cancellations}_controller.rb,
app/controllers/concerns/authentication.rb (login merge), app/controllers/messages_controller.rb (rate limit),
app/services/offers/accept.rb (race fix); app/views/{carts,checkouts,addresses,orders,sell/sales,reviews,order_mailer}/*;
test/{models,services,jobs,controllers,controllers/sell,fixtures}/* (new files above),
test/integration/sell_dashboard_test.rb + sell_vacation_test.rb (fixture-number rename / buy-button label),
test/integration/messaging_test.rb (429 via Rails.cache).

## 2026-11-17 — Phase 4a: internal chat & offers (threads, Turbo real-time, blocks, offer decisions, expiry job)

**What changed**

- Routes (all inside the `(:locale)` scope, auth required):
  `resources :conversations, only: %i[index show create]` with nested
  `resources :messages, only: :create` + `resource :read_receipt, only: :create`;
  `resources :blocks, only: %i[index create destroy]`; `listings` nest
  `resources :offers, only: %i[new create]`; `resources :offers, only: :index`
  plus singular `resource :acceptance / :decline / :withdrawal` (POST) under
  `/:locale/offers/:offer_id/...`.
- Migrations (applied, structure.sql updated): `20261117210001` messages gain
  `kind` enum (text/offer/system) + `offer_id` FK; `20261117210002` listings
  gain `reserved_for_id` FK + `reserved_until` (status enum already had
  `reserved`).
- Models: `Conversation.for_user` scope (the ONLY lookup path controllers use →
  outsiders 404), `other_party`, `blocked_by?`, `unread_count_for`,
  `unread_badge_count_for` (Rails.cache per user), `unread_counts_by_conversation_for`
  (batched inbox counts), `mark_messages_read_for`. `Message`: `MAX_BODY_LENGTH =
  2000`, safety-tip regex patterns (`safety_flagged?`, advisory banner only),
  `after_create :touch_conversation` + `after_create_commit :broadcast_creation`
  (append bubble to the conversation stream, replace the inbox row on each
  participant's `[user, :inbox]` stream, clear the unread caches). `Offer`:
  `OFFER_TTL = 48.hours`, `for_seller` / `sent_by` / `active` / `not_expired`
  scopes, `accept!`/`decline!`/`withdraw!` (stale-safe), `expire!` for the job.
  `Listing`: `RESERVATION_TTL = 48.hours`, `reserve_for!`/`release_reservation!`
  transitions, `reserved` status. `Notification.recent_unread_message_for?`
  (e-mail throttle probe). `Setting::DEFAULTS` gains `min_offer_percent` (50).
- Services: `Conversations::Start` (find-or-create per listing+buyer, refuses
  self + blocked pairs), `Messages::Send` (participant/block/blank/length
  guards, then Notification + e-mail only if no unread `new_message`
  Notification for that thread in the last 15 min), `Offers::Create`
  (approved+offers-allowed+not-on-vacation, amount < price and ≥
  `ceil(price × min_offer_percent / 100)` via `Offers::Create.minimum_for`,
  withdraws the buyer's older pending offers, posts an offer card into the
  thread, `new_offer` Notification), `Offers::{Accept,Decline,Withdraw}`
  (accept reserves the listing for the buyer + auto-declines every other
  pending offer + `offer_accepted` Notification; stale decisions return
  `:stale`). `ExpireOffersJob` expires pending offers and releases lapsed
  reservations; scheduled in `config/recurring.yml` every 15 minutes.
- Controllers (skinny; every read scoped through the model APIs):
  conversations (GET show marks the thread read), messages (create only;
  `RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new` constant +
  `rate_limit to: 30, within: 1.minute, by: Current.user.id` → 429; turbo
  replies just clear the composer), read_receipts (marks read + re-renders the
  `shared/_unread_conversations_badge` partial on the user's stream), blocks
  (create/destroy via `current_user.blocks_cast`; `:cannot_block_self` /
  uniqueness `:taken` flash), offers (`@received_count`/`@sent_count` tab
  counts; `find_offerable_listing` 404s for owners and non-approved EXCEPT
  reserved, which renders the form's 422 `not_allowed` message instead),
  acceptances/declines/withdrawals (redirect to the thread with
  notice/`offers.decisions.stale` alert).
- Views: `conversations/{index,show,_row,_tabs,_composer}` (show = inbox rail +
  thread; `_row` takes `viewer:` + batched `unread:`, its `id=dom_id` is the
  broadcast target), `messages/{_message,_offer_card}` (message renders NEUTRAL
  — alignment is client-side), `offers/{new,index,_row}`, `blocks/index`,
  `shared/_unread_conversations_badge` (header, after the cart icon).
  `turbo_stream_from` tags: thread card (`@conversation`) + inbox rail/list
  (`current_user, :inbox`) — turbo-rails 2.x signs stream names (GID-based).
- Stimulus: `thread_controller.js` (reads `data-thread-current-user`, toggles
  `justify-end` on `[data-message]` rows + `bg-primary text-white` on
  `[data-bubble]`, re-aligns appended bubbles via MutationObserver on
  `#messages`), `composer_controller.js` (submitting state). `ConversationsHelper#user_initials`.
- listings/show wiring: "message seller" `button_to conversations_path`
  (hidden for owner, disabled when sold), real make-offer link when
  `!on_vacation && offers_allowed? && !owner` else disabled chip with
  `.offers_disabled`/`.vacation_cta`/`.reserved_cta` title, reserved banner
  (`listings.show.reserved_banner` with `l(reserved_until, format: :long)`),
  `:messaging` Flipper gate removed (real feature now); `stripe_checkout` gate kept.
- `MessageNotificationMailer#new_message` (html+text, renders in the
  recipient's locale, safety tip in the footer).
- I18n: new key trees (conversations, offers, blocks, messages.create.errors,
  acceptances/declines/withdrawals, listings.show.reserved_*,
  message_notification_mailer.new_message, time/date `chat_day`/`chat_time`)
  across all 6 locales — `script/lint_locale_keys.rb` green at 759 keys.
- Design tokens: `.input`, `.btn-primary`, `.chip`, `.chip-active` component
  classes (+ UA-strip rules because `button_to` puts the class on the FORM
  wrapper) in `app/assets/tailwind/application.css`; new views use
  token classes (text-text/text-muted/border-border/bg-surface-muted/
  bg-primary), amber = advisory, rose = destructive.

**Gotchas recorded**

- `body = body.to_s.strip` inside a no-param method rebinds to an **nil local**
  instead of calling the attr_reader — every Send call returned `:blank`.
  Use a distinct local (`text = ...`).
- User display name is `User#display_name` (store name or username) — `name`
  does not exist; Store/Category/Label do have `name`.
- `content_for :title = t(...)` is a syntax error; use `content_for :title, t(...)`.
- Turbo broadcasts fire even in transactional tests here (Rails 8.1 fixtures),
  and `capture_turbo_stream_broadcasts` returns **Nokogiri elements** — assert
  via `el["action"]`/`el["target"]`/`el.to_html`. Model/service tests therefore
  render `_row`/`_message` partials — they must never need `current_user`.
- `perform_enqueued_jobs` dequeues → `assert_enqueued_emails` AFTER the block
  sees 0; assert inside, or don't perform at all.
- Integration `flash` accessor merges previous request's still-pending flash
  across POST→POST chains; assert positives (`assert_equal ..., flash[:notice]`).
- `money` helper lives in `ListingsHelper` (view context only) — controllers
  format with `Money.new(cents, currency).formatted` (en renders `€300.00`).
- Seeds test asserts the DEFAULTS count: now **5** settings (`min_offer_percent`).
- Rate limiting: dedicated `MessagesController::RATE_LIMIT_STORE` so tests can
  clear it without touching the fragment-cache store.

**Tests** (suite: 274 runs / 0 failures / 0 errors; rubocop clean on 202 files;
locale lint green; tailwind build clean): new `test/models/{conversation,
message,offer}_test.rb`, `test/services/conversations/start_test.rb`,
`test/services/messages/send_test.rb`, `test/services/offers/{create,decisions}
_test.rb`, `test/jobs/expire_offers_job_test.rb`, `test/mailers/message_notifi
cation_mailer_test.rb`, `test/integration/{messaging,offers,turbo_broadcasts}
_test.rb` (messaging: inbox scoping, start/self/block refusals, read receipts,
30/min 429 loop, blocks CRUD errors; offers: form hints in en money format
`€300.00`, decision flows, reserved 422 + banner, tab scoping; broadcasts:
thread append + both inbox-row replaces + `turbo-cable-stream-source` tags).

**Files touched**: config/{routes,recurring}.yml; db/migrate/202611172100{01,02}*.rb;
db/structure.sql; app/models/{conversation,message,offer,listing,notification,setting,money}.rb;
app/services/{conversations/start,messages/send,offers/{create,accept,decline,withdraw}}.rb;
app/jobs/expire_offers_job.rb; app/mailers/message_notification_mailer.rb +
views/message_notification_mailer/*; app/controllers/{conversations,messages,read_receipts,blocks,offers,acceptances,declines,withdrawals}_controller.rb;
app/helpers/conversations_helper.rb; app/assets/tailwind/application.css;
app/javascript/controllers/{thread,composer}_controller.js;
app/views/{conversations/*,messages/*,offers/*,blocks/index,shared/_unread_conversations_badge};
app/views/layouts/_header.html.erb; app/views/listings/show.html.erb;
config/locales/*.yml; the test files listed above.

## 2026-11-17 — Phase 3b: seller dashboard, store settings, vacation mode (+ photo-purge bugfix)

**What changed**

- Bugfix first: `Listings::Update#call` wrapped save+purge so ActiveStorage
  purges (`attachment.purge_later`) run only AFTER commit — a failed update
  with `remove_photo_ids` keeps the photos attached (also fixes a latent
  `saved: true` after rollback). Regression tests in
  `test/integration/sell_listings_test.rb`.
- Routes: `namespace :sell` gains `resource :dashboard, only: :show` (+
  `root to: "dashboards#show", as: :sell_root`), `resource :store, only:
  %i[edit update]`, `resource :vacation, only: %i[create destroy]` and
  `resources :sales, only: %i[index show]` (read-only; shipping actions are
  Phase 4).
- Sell chrome: `Sell::BaseController` uses `layout "sell"`
  (`app/views/layouts/sell.html.erb`, noindex) with the `sell/_sidebar`
  partial — store card (logo or 2-letter initials, name, @username) + nav
  (Dashboard / My listings / My sales / Public profile / Store settings /
  Vacation toggle). Nav row scrolls horizontally on mobile, vertical rail
  from `lg`. Header account dropdown + mobile menu gained "My store" links.
- Dashboard (`Sell::DashboardsController` + `Sell::DashboardStats`): every
  number from aggregate queries only (one per metric). KPIs: live/in-review
  listings and lifetime views (current), favorites/sales/revenue windowed
  to 30 days (revenue = `SUM(total_cents − commission_cents)` on completed
  only, via new `Order#net_revenue_cents`), zero-guarded conversion. 12-week
  pure HTML/CSS bar chart from ONE `date_trunc('week', …)` GROUP BY,
  zero-filled oldest-first (`Result#weekly_max`). "Needs attention" =
  recently rejected + reasons (`Listing.recently_rejected_for`), pending
  offers (`Offer.pending_for_seller`), unanswered threads
  (`Conversation.unanswered_for_seller` = NOT EXISTS seller message). Top 5
  by views. Stats fragment cached 5 min per store.
- Store settings (`Stores::UpdateSettings` + singular `resource :store`):
  name unique 2..60, description ≤2000, store_type enum individual/business
  (business requires `vat_number` validated by new
  `app/validators/spanish_tax_id_validator.rb` — NIF/NIE/CIF checksums incl.
  CIF control-char table `JABCDEFGHI`), city + `region` (EsProvince),
  returns/shipping policies, shipping defaults posted as euro strings
  (`store[default_shipping]` → cents), logo/banner uploads (jpeg/png/webp,
  5 MB/8 MB model validations, variants: logo thumb 256²/card 400², banner
  display 1600×400). FriendlyId `:history`: renaming regenerates the slug
  and public `StoresController#show` 301-redirects old slugs.
  New migrations `20261117200001` (settings), `…200002`
  (friendly_id_slugs), `…200003` (stores.city/region).
- Vacation mode: `Store#enable_vacation!`/`disable_vacation!` via
  `Sell::VacationsController` (POST/DELETE /sell/vacation). Listings stay
  visible in search (ListingSearch untouched) but public listing pages show
  a "seller on vacation" notice and buy/offer CTAs are disabled; store page
  gets a vacation banner.
- My sales: `Sell::SalesController#index/show` — seller-scoped orders
  (`Order#net_revenue_cents`), status badges via `Sell::SalesHelper`,
  read-only show for now. New `test/fixtures/order_items.yml` links
  fixture orders to listings.
- Gotchas learned: FriendlyId `:history` `after_save :create_slug` records
  the CURRENT slug — fixture INSERTs create no history rows, so tests that
  exercise old-slug resolution must seed `store.slugs.create!(slug:)` or
  create stores through the model. Lazy attachment assignment
  (`store.logo = file`) is deferred until save: on a 422 re-render the
  in-memory attachment has no `signed_id`, so `store_logo_url`/
  `store_banner_url` require `attached? && persisted?` (and note
  `store&.logo.attached?` only guards `logo` — use `&.attached?`).
- Locales: 6 files merged to an identical tree of **679 keys**
  (`ruby script/lint_locale_keys.rb` green).

## 2026-11-16 — Phase 3a: seller listing management (sell namespace CRUD, review submission, photo upload)

**What changed**

- Routes: `namespace :sell { resources :listings }` plus singular POST-only
  `resource :submission` / `:archival` / `:sale_mark` nested under listings and
  `resources :category_fields, only: :show` (Turbo Frame endpoint, lookup by
  **category** slug). All inside the locale scope; `Sell::BaseController`
  requires authentication and redirects banned users (`User#banned?`) to root
  with the suspension alert. Header CTAs ("List an item", mega-menu, mobile
  menu) now link to `new_sell_listing_path` instead of `#`.
- `Sell::ListingsController`: every lookup via
  `current_user.listings.friendly.find` → other sellers' listings are 404.
  Index has status tabs (all/draft/pending_review/approved/rejected/sold/
  archived) with per-tab counts from ONE `group(:status)` query
  (`Listing.status_counts`) and pagy (`results_pagination`). Destroy only for
  draft/rejected/archived (`Listing#destroyable?`), otherwise 422 + inline
  message.
- Services: `Listings::FormAttributes` (euro-string → cents with ES thousand
  separators, category slug resolution, spec normalisation/casting per
  `input_type`, seller-tag slugs, allow_offers tri-state), `Listings::Create`
  (auto-creates the seller's individual store via `Stores::EnsureFor` on first
  listing, name = username), `Listings::Update` (MATERIAL columns + photo
  changes on an APPROVED listing → `request_revalidation!` back to
  pending_review; price/shipping/location edits keep it live; attach/purge
  inside the transaction so failed saves roll photos back), `Listings::Submit`
  (submit_for_review! + batched admin `Notification.insert_all` in one txn).
- Model additions: `Listing#archive!`, `#request_revalidation!`,
  `#destroyable?`, `.status_counts`; validations for postal code format
  (`POSTAL_CODE_FORMATS`), ES province names (`EsProvince` + `config/data/
  es_provinces.yml`), photo content types/sizes/count, seller-tag limit,
  `validate_required_specs` on the `:submission` context only (unknown spec
  keys/values rejected in ALL contexts; boolean `false` counts as present).
- Form: single page (`sell/listings/_form`) driven by new Stimulus
  `listing_form_controller.js` — category picker reloads `#spec_fields` Turbo
  Frame from `sell_category_field_path(category_slug)`, title counter, photo
  input + drag-drop with client-side I18n error messages, tag limit. Server
  re-render only shows persisted, image-type attachments (rolled-back
  attachments can't be varianted). "Save draft"/"Submit for review" are two
  submit buttons distinguished by top-level `intent` param.
- Errors: `shared/_error_summary` partial + `activerecord.errors.messages`
  keys (spec_key_unknown, spec_required, spec_value_*, photo_*,
  original_price_below_price, invalid_postal_code, province_unknown…).
- Fixtures/tests: `users(:banned)` added; draft fixture specs fixed to match
  category spec attributes. `test/integration/sell_listings_test.rb` (20
  tests): auth + banned, index scoping/tabs, draft+store creation, submit +
  admin notification, 404 across sell area for foreign listings, material vs
  price-only edit rules, submission endpoint, archive/sold/destroy rules,
  photo + spec validation messages, category_fields frame.

**Gotchas learned**

- `Listing.human_attribute_name(:condition)` raises — the node is a hash;
  use `t("listings.filters.condition")` for the legend.
- Form param names must match what the services read: form posts
  `listing[price]` / `[original_price]` / `[shipping_price]` as EURO strings
  (never the `_cents` columns), and `FormAttributes` guards every field with
  `raw.key?(…)` so partial PATCHes don't nil out prices.
- `permit(specs: {})` passes arbitrary scalar spec values through; unknown
  keys surface as model validation errors rather than dropped params.
- Controllers must rescue with `=> e` when re-raising message (submissions
  `RecordInvalid` alert).

**Verification**: 158 runs / 993 assertions / 0F / 0E; rubocop clean (152
files); locale lint: 567 keys × 6 files; tailwind build clean. Not committed.

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
