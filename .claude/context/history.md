# History

## 2026-11-17 — Phase 9: demo seed with real photos (image APIs, attribution, Spanish catalog)

**What changed**

- **Image provider services** (`app/services/demo_images/`):
  `Fetcher` (orchestrator: provider priority Pexels→Pixabay→Openverse,
  per-query on-disk pool cache `tmp/demo_images/<query-slug>/manifest.json`,
  magic-byte validation jpeg/png/webp, 8 MB download cap, content type
  from sniffed bytes), `Placeholder` (ImageMagick gradient tiles with
  category name, always succeeds), `Providers::Base` (shared Net::HTTP
  get_json: 10 s timeouts, 8 MB stream cap, custom UA `PCMarketSeed/1.0`
  — required by Openverse, Cloudflare 403s the Ruby default),
  `Providers::Openverse` (no key; `license_type=commercial,modification`
  server-side filter + client-side `ALLOWED_LICENSES` re-check (by,
  by-sa, cc0, pdm, zero); 3 s inter-call throttle + class-level
  `min_call_interval` test seam), `Providers::Pexels`/`Providers::Pixabay`
  (activate only with `PEXELS_API_KEY`/`PIXABAY_API_KEY`). **Unsplash
  deliberately NOT implemented**: its API requires clients to load the
  source URL on every render for hotlink-protection counting, which is
  incompatible with one-shot seed-time downloads — documented in
  `providers/base.rb`.
- **Attribution end-to-end**: provider metadata (creator, creator_url,
  license, license_url, source_url, provider) stored in
  `blob.metadata["attribution"]`; `ListingsHelper#photo_credit_tag`
  renders "Foto: <creator> · <license> vía <provider>" (creator + source
  linked) inside each gallery slide of `listings/show`
  (`listing.photo_credit` key, all 6 locales).
- **New seed** `db/seeds/demo.rb` (`module DemoSeed`, called from
  `db/seeds.rb` in dev or with `SEED_DEMO=1`; refuses production unless
  `ALLOW_DEMO_SEED=1`): `SEED_LISTINGS` (default 300), `SEED_RESET=1`,
  `SEED_SEED=` reproducible randomness; **idempotent** via fixed
  `*@demo.pcmarket.test` emails + top-up semantics (a second run creates
  zero listings). Replaces `sample_listings.rb` (DELETED; a one-time
  `cleanup_legacy_samples!` destroys the old `*@pcmarket.test` users +
  their orphan slugs first).
- **Data**: Faker `:es` locale, Spanish descriptions/questions/replies/
  addresses; catalog `db/seeds/data/demo_catalog.yml` (52 leaves: model
  names + realistic € ranges + sample spec presets); business stores
  with valid **CIFs computed via `SpanishTaxIdValidator.cif_control`**,
  ImageMagick logo/banner attachments, policy pages; specs filtered
  against the leaf's real options (`valid_specs_for`); photo blobs
  uploaded with `identify: false` + explicit width/height metadata
  (analyzer jobs are skipped on this path and `vite_image_tag` needs
  dimensions) + attribution. Status mix 70/10/5/10/5
  (approved/sold/draft/pending/reserved), ~15% with strikethrough
  `original_price_cents`, `featured_until` ~12%.
- **Graph**: favorites (some auto-cleared through sold orders), follows,
  saved searches, Spanish conversations with unread counts, offers in
  every state (acceptances through `accept!` so counters stay true),
  orders walked through the real state machine then backdated via
  `update_columns` (disputes opened BEFORE backdating to respect the
  15-day window; past-deadline ones resolved by the admin), refunds
  after disputes (auto-resolve refunded), reviews for delivered/
  completed orders, notifications, reports (≤3 per listing so flood
  revalidation isn't triggered), contact messages, newsletter prefs,
  moderation events, labels + seller tags.
- **App bug fixed along the way**: `Order#has_one :review` was
  `dependent: :nullify` while `reviews.order_id` is NOT NULL — destroying
  any reviewed order raised a NotNullViolation (surfaced by seed
  cleanup; regression test in `review_test.rb`). Now `dependent: :destroy`
  (Review's destroy callback already refreshes store ratings).
- **Tests**: webmock added to the test group
  (`disable_net_connect!` in `test_helper`); new
  `test/services/demo_images/{openverse,fetcher}_test.rb` (Openverse
  parse + non-commercial filtering, pool cache reuse, placeholder
  fallback, magic-byte rejection), `test/seeds/demo_seed_test.rb`
  (idempotent 20-listing run + CIF validity),
  `test/integration/listing_photo_credit_test.rb` (credit renders with
  string-keyed blob metadata). Suite: **748 runs green**. rubocop 0
  offenses (`test/services` + `test/seeds` excluded — intentionally
  invalid payloads), locale lint 2657 keys aligned, eager_load clean.

**Gotchas**

- Blob `metadata` reads return STRING keys (`meta["attribution"]`, not
  `meta[:attribution]`) — the helper and tests must match.
- `vite_image_tag` raises "supports only images with width and height"
  when blob metadata lacks dimensions; `identify: false` uploads skip
  the analyzer, so the seed writes width/height itself (from `magick
  identify`, default 800×600 — helpers clamp to that anyway).
- `open_dispute!` requires the order <15 days past delivered_at — seed
  opens disputes before backdating timestamps.
- Order destruction cascades through the `has_one :review` fix;
  `has_many :reviews` on Store stays `:nullify` (store_id IS nullable).
- Seed wall time is dominated by cold pool fetches (~52 unique category
  queries × 3 s throttle); re-runs with a warm `tmp/demo_images` are
  fast. Placeholder fallback works fully offline.
- **Graph section made per-step idempotent (top-up)**: removed the
  "favourites exist → skip graph" guard; every step now counts what demo
  users already have and only creates the missing rows to reach the new
  `GRAPH` targets + `ORDER_PLAN` state distribution (orders diff against
  existing demo orders and skip sold listings that already have one;
  notifications/contact messages/close-one-report have their own
  exists?-style markers), with progress output per step — an interrupted
  seed re-run now completes the graph (verified on dev: 59-listing
  top-up + full graph in one pass, second pass a no-op).

## 2026-11-17 — Phase 8b: JSON API v1 (bearer auth, full REST surface, OpenAPI docs, devices)

**What changed**

- **Routing**: `namespace :api { namespace :v1 }` in `config/routes.rb`, deliberately
  OUTSIDE the `(:locale)` scope — language is negotiated with `Accept-Language`,
  not the URL (a `/es/api/v1` duplicate would fork cache keys; `route_actions_test`
  asserts it never routes). `defaults format: :json`; public docs routes
  `/api/v1/docs` (Redoc HTML) and `/api/v1/openapi` (serves the hand-written
  3.1 spec from `public/api/v1/openapi.yaml`, 2251 lines).
- **Auth**: `Api::V1::BaseController` (plain `ActionController::API`) resolves
  `Authorization: Bearer <token>` through `ApiToken.authenticate` (the Phase 1
  model: SHA-256 digest, `active` = `expires_at IS NULL OR > now`, stamps
  `last_used_at`); `Current.api_token` added and `Current.user` now falls back
  to the API user. Banned accounts → 403 `banned`. Public endpoints
  (`listings`, `stores`, `config`, …) skip the callback and use
  `authenticate_token_if_present` so token owners still see their own drafts.
  Token-issuing endpoints: `POST /session` (10/min/IP throttle), `DELETE
  /session` revokes, `POST /registration`, `POST /password_reset`, `GET /me`,
  `GET/DELETE /api_tokens` (device-side token management).
- **Error envelope**: every failure renders
  `{ error: { code, message, details } }` via `render_error` —
  `rescue_from` maps RecordNotFound→404, RecordInvalid→422 (details =
  `record.errors.as_json(full_messages: true)`), ParameterMissing→400,
  `Api::V1::Forbidden`→403, `Listing::InvalidTransition`→409. State changes are
  modelled exactly like the web: singular nested POST resources (`submission`,
  `archival`, `sale_mark`, `acceptance`, `decline`, `withdrawal`, `shipment`,
  `payment_confirmation`, `delivery_confirmation`, `completion`, `cancellation`,
  `dispute`). Scoping is the web's: outsiders 404 (never 403), buyer vs seller
  transitions 404 across roles.
- **Rate limiting**: global `rate_limit to: 300, within: 1.minute` keyed by
  token id (remote IP while anonymous) → 429 with the same envelope; the test
  memory cache makes it exercisable (`throttling_test`).
- **Pagination/conditional GET**: list endpoints return `meta.pagination`
  (`page/per_page/total/total_pages`) plus a `Link` header
  (`rel="first|prev|next|last"`, `set_link_header`); catalogue/config use
  `fresh_when strong_etag:` (strong validators — Rack only echoes strong ETags
  back, so a weak one could never match its own If-None-Match) → 304. Messages
  page with a `?before_id=` cursor (chronological page back).
- **Surface mirrors the web app**: catalogue (listings index = `ListingSearch`
  with `f[attr]` spec filters, facets + echoed filters in `meta`; store
  listings/reviews/follow; categories; countries), `GET /config` (category
  tree, localized enum/sort/PC-finder labels, carriers, `flags` = every
  `FeatureFlags::FEATURES` key as a boolean, `min_app_version` from two new
  nil-default Settings), engagement (favorites, saved searches, notifications
  + mark-all-read), conversations/messages, offers (+accept/decline/withdraw),
  cart/checkout (direct-buy mode and conversation-offer ids), orders with all
  transitions + review, PC Finder, and the sell area (dashboard, listing
  create/update, submission/archival/sale_mark).
- **Direct uploads**: `POST /api/v1/direct_uploads` mirrors
  ActiveStorage::DirectUploadsController's JSON shape over bearer auth (the
  engine's is cookie+CSRF). Needs `include ActiveStorage::SetCurrent` or the
  disk service can't sign its PUT URL ("Missing host to link to!"). Client
  PUTs the bytes to the returned url+headers (disk answers 204), then puts the
  `signed_id` into listing create/update `photos`.
- **Devices**: `Device` model + migration `20261118060000` (user FK,
  `push_token` ≤4096 unique per user, `platform` ios|android) with
  index/create/destroy endpoints — registry only, no push sender wired yet.
- **Action Cable**: `ApplicationCable::Connection` accepts the same bearer
  token via `?token=` or the Authorization header (native apps have no
  cookies), falling back to the session cookie.
- **CORS**: `rack-cors` (new gem) in `config/initializers/cors.rb` —
  `/api/*` is cross-origin only for origins in `API_CORS_ORIGINS`; exposes
  `Link`/`ETag`.
- **Tests** (13 request specs in `test/integration/api/v1/` + channel test):
  `route_actions_test` (every api/v1 route resolves to a real action, ≥60
  routes, locale-prefixed API paths must NOT route), `openapi_coverage_test`
  (routes↔spec both directions, verb-exact), `listings_test` (pagination
  meta + Link header, `f[...]` filters, facets, ETag 304, draft 404, Accept-
  Language `fr`, N+1 guard via `api_query_count`), `config_test` (flags
  booleans, Flipper on/off), `engagement_test` (favorites, saved searches,
  notifications),
  `conversations_messages_test` (before_id cursor, outsider 404),
  `offers_test`, `cart_checkout_test`, `orders_transition_test` (buyer
  cannot ship), `sell_test` (direct upload → signed_id → create with photo →
  submission → pending_review), `devices_test`, `auth_test`,
  `throttling_test`; `connection_test.rb` for Cable bearer auth.

**Why**

Native clients need the same rules as the web without cookies or CSRF: one
bearer credential reused by REST and Action Cable, state transitions as
resources (never magic PATCH fields), and a spec kept honest by a test that
diffs routes against `openapi.yaml`. The Phase 1 `ApiToken` model was already
right — only expiry scope + stamping are used now.

**Gotchas learned**

- `ActionController::API` does NOT auto-include app helpers or the translation
  proxy: `helper Api::V1::SerializationHelper` + `include
  AbstractController::Translation` in the base controller.
- Iterating `listing.photos` yields `ActiveStorage::Attachment` records (which
  `delegate_missing_to :blob`) — `attached?` exists on neither, so the
  serializer guard is `attachment.persisted? && attachment.blob&.persisted?`
  (the fixture catalogue has no photos, which is why this latent bug only
  surfaced once an upload test attached one).
- Integration-test headers: underscore names like `ACCEPT_LANGUAGE` never
  become `HTTP_ACCEPT_LANGUAGE` env vars (ActionDispatch only upcases
  `[A-Za-z0-9-]+` names); send the real header name (`"Accept-Language"`).
- Rails 8.1's per-connection query cache keeps working ACROSS requests in one
  test (repeat SQL re-emits `sql.active_record` events with `cached: true`);
  `api_query_count` counts those events on purpose (skipping them makes the
  second request count 0 and the guard vacuous). The listings N+1 guard
  compares limit 5 vs 100 with a +1 tolerance: the 100-row page contains the
  two labelled listings, and Active Record skips the whole `Label` preload
  when the join query returns no rows — a real per-row loop still blows past
  the +1 and the ≤16 cap.
- Action Cable test helper is `assert_reject_connection` (8.1 naming).
- Fixtures have no user photos at all, so any ActiveStorage attach in an API
  test needs a real `create_and_upload!`/direct-upload round trip.

**Files touched**: `Gemfile` (+`rack-cors`), `config/routes.rb`,
`config/initializers/cors.rb`, `app/controllers/api/**` (41 controllers incl.
`api/v1/base_controller.rb`, `sell/`), `app/errors/api/v1/forbidden.rb`,
`app/helpers/api/v1/serialization_helper.rb`, `app/views/api/v1/**`
(jbuilders incl. `partials/_listing_card|_listing_full`), `app/models/device.rb`,
`app/models/current.rb`, `app/models/user.rb` (+`has_many :devices`),
`app/models/offer.rb` (+`has_one :seller, through: :listing`), `app/models/setting.rb`
(+2 nil-default app-version keys, `seed_defaults!` skips nils),
`app/channels/application_cable/connection.rb`, `db/migrate/20261118060000`,
`public/api/v1/openapi.yaml`, `config/locales/*.yml` (`api.*` keys — 2656 now),
`test/test_helpers/api_v1_test_helper.rb`, `test/integration/api/v1/**`,
`test/channels/application_cable/connection_test.rb`.

## 2026-11-17 — Phase 8a: SEO (meta tags + JSON-LD, robots.txt, sitemap, localized error pages, brand assets)

**What changed**

- **Meta pipeline (meta-tags gem)**: `SeoHelper#set_meta` (single entry
  point called from every public view) renders title, description,
  canonical, Open Graph (incl. `product:price` extensions + og:locale +
  `locale:alternate`), Twitter summary_large_image and hreflang. Canonical
  strips `TRACKING_PARAMS` always; filterable pages (listings index,
  categories, pc-finder results, stores) keep their filter/facet params
  via `seo_kept_params` (`sort` and `page=1` dropped). `es` is the
  unprefixed form, so each page has ONE canonical; hreflang alternates
  (6 locales + `x-default`) render only on indexable pages. Application
  layout: `display_meta_tags site: site_name, reverse: true, separator:
  " | "` + theme-color meta + favicon set + `site.webmanifest` link.
- **Robots directives**: `Seo` concern (all controllers): `NOINDEX_AREAS`
  (admin/sell/account/carts/checkouts/auth/messaging/offers/orders/…) →
  `robots: noindex,follow` meta in a before_action + `X-Robots-Tag:
  noindex, follow` header in an after_action. Dynamic rules evaluated in
  views: free-text `q` search, **>2 facet groups**
  (`ListingsHelper#seo_filtered_browse_count`; price band counts once,
  path category doesn't count) and zero-result pages are noindexed. The
  pre-8a hardcoded `<meta name="robots" content="noindex">` + manual
  `<title>` in the admin layout were replaced by `display_meta_tags
  site: false, title: content_for fallback` so the concern is the single
  robots source everywhere.
- **JSON-LD**: `JsonLdHelper` builders — Organization (+sameAs from
  `social_links`) + WebSite (+SearchAction) on home, BreadcrumbList on
  listing/category/store pages, Product+Offer (availability `SoldOut` for
  sold listings, `itemCondition` mapped from the condition enum, Brand
  from brand-ish specs, seller Organization/Person), store Organization
  with AggregateRating ONLY when `reviews_count > 0`, ItemList (first 24,
  page 1 only) on categories, FAQPage on `/pages/help`. `json_ld_tag`
  renders `tag.script(payload.to_json.html_safe, type:
  "application/ld+json")` — ActiveSupport's `to_json` escapes `<`/`>`/`&`
  as `\u003c`…, which already prevents `</script>` breakout; a follow-up
  `json_escape`/`gsub`/ERB pass would corrupt the JSON and must NOT be
  added. Regression test: listing titled `…</script><script>alert(1)
  </script>…` → the ld+json block parses with `JSON.parse`, round-trips
  the title, and contains no literal `</script>`.
- **robots.txt**: static `public/robots.txt` deleted; route `get
  "robots.txt" => "robots#show"` (outside the locale scope — must be at
  the domain root). `RobotsController` renders disallow-all UNLESS
  `Rails.env.production? && Setting.search_engine_indexing?`; then
  `Disallow: /*/<area>` + `/<area>` pairs for every private area + the
  `Sitemap:` line. New Setting `search_engine_indexing` (DEFAULTS: true
  only in production) — seeded settings are now **7**.
- **Sitemap**: `config/sitemap.rb` (sitemap_generator): every URL added
  in all six locale variants, each carrying `xhtml:link` hreflang
  alternates back-linked across locales; home/trust/pc-finder/content
  pages/active categories/published listings/stores with
  listings/legal slugs. Output to `public/sitemaps/` (gitignored; dev
  run: 769 URLs). `SitemapRefreshJob` + daily 3am recurring entry. Tests
  run the Interpreter against a temp dir via `SITEMAP_PUBLIC_PATH` +
  `APP_URL` and assert published-listing URLs (draft/pending/sold
  absent) and alternates. GOTCHA: sitemap_generator renders xhtml:link
  attributes in fixed `rel`/`href`/`hreflang` order — assert in that
  order.
- **Localized error pages**: static `public/404|422|500.html` deleted;
  `config.exceptions_app = self.routes` in test + production; routes
  `/404`, `/422`, `/500` → `ErrorsController` (recovers the locale from
  `action_dispatch.original_path`, `layout "errors"`, noindex). GOTCHA:
  in the test env DebugExceptions still wins for UNROUTED urls — assert
  localized content through `/404` with an explicit
  `env: { "action_dispatch.original_path" => "/fr/…" }`.
- **Listing slug history**: FriendlyId `:history` on Listing +
  `ListingsController#show` 301 when `listing.slug != params[:id]`
  (same pattern as stores).
- **Brand assets**: `public/favicon.ico`, `icon-32/192/512.png`,
  `apple-touch-icon.png`, `og-default.png` (default `og:image` via
  `SeoHelper::DEFAULT_OG_IMAGE`), `site.webmanifest`; application,
  account, sell, admin and errors layouts link the set.

**Tests added**

`test/integration/seo_test.rb` (meta title/description/canonical per page
type, hreflang=7 incl. x-default, noindex rules incl. >2 filters,
cart/checkout/account/sell/admin/auth meta + X-Robots-Tag, JSON-LD
@types per page incl. SoldOut + FAQPage, hostile-title JSON-LD safety);
`test/integration/robots_txt_test.rb` (both setting states);
`test/integration/sitemap_test.rb`; `test/integration/error_pages_test.rb`
(404/422/500 statuses + localized 404); `test/integration/listing_slug_
history_test.rb`. Fixed from the first pass: sitemap alternate assertions
now expect the gem's attribute order; seeds test expects 7 settings.

**Files touched**

`app/controllers/concerns/seo.rb` (new), `app/helpers/seo_helper.rb`
(new), `app/helpers/json_ld_helper.rb` (new), `app/controllers/robots_
controller.rb` + `app/controllers/errors_controller.rb` (new),
`app/views/errors/*` + `app/views/layouts/errors.html.erb` (new),
`app/jobs/sitemap_refresh_job.rb` (new), `config/sitemap.rb` (new),
`app/views/layouts/{application,admin,account,sell}.html.erb`,
`app/views/pages/*`, `app/views/listings/{index,show}.html.erb` and the
other public views (`set_meta` + JSON-LD), `app/controllers/
{listings,application}_controller.rb`, `app/helpers/listings_helper.rb`,
`app/models/{listing,setting}.rb`, `app/services/admin/settings.rb` +
`app/views/admin/settings/edit.html.erb` (indexing toggle),
`config/{routes,recurring}.yml`, `config/environments/{test,production}.rb`,
`.gitignore`, `config/locales/*.yml`, the five new/updated test files
above.

## 2026-11-17 — Phase 7f: legal corpus for Italy (IT/it) and Portugal (PT/pt) + FR returns presumption fix

**What changed**

- `db/seeds/legal/FR/fr/returns.md` — corrected the presumption of
  non-conformity sentence: 24 months for new goods and 12 months for
  second-hand goods (C. conso art. L217-7), replacing the previous
  blanket "12 months for all goods".
- `db/seeds/legal/IT/it/` — eight Italian templates adapted to Italian +
  EU law: legal_notice cites D.Lgs. 70/2003 art. 7 identification
  ({{legal_name}}, {{registered_address}}, {{tax_id}}, Registro
  Imprese/REA {{registry}}) with bracketed TODO markers for capitale
  sociale and PEC; terms cover the intermediary role (artt. 16-17
  D.Lgs. 70/2003 + DSA), 18+, ranking transparency via Reg. 2019/1150 +
  DSA art. 27 + Codice del consumo art. 22 c. 4-bis, DSA arts. 16-17,
  20-21, 23 duties, 0 % fees with 15-day notice, Italian law with the
  foro del consumatore (art. 66-bis Codice del consumo); privacy cites
  GDPR + D.Lgs. 196/2003 as amended by D.Lgs. 101/2018, DAC7 via
  D.Lgs. 32/2023 reporting to the Agenzia delle Entrate, Garante
  complaint (garanteprivacy.it); cookies cites art. 122 Codice privacy +
  Garante guidelines of 10 June 2021 (no cookie wall, scroll is not
  consent, consent re-ask no sooner than 6 months) with the shared
  strictly-necessary cookie table; returns covers C2C (no recesso, arts.
  1490 ff. c.c. hidden-defect route) vs B2C (14-day diritto di recesso,
  artt. 52 ss. with modulo tipo; garanzia legale di conformità 2 anni,
  artt. 128 ss. as amended by D.Lgs. 170/2021, reducible to min. 1 year
  for used goods, 12-month presumption); buyer_protection, seller_terms
  (traders: DSA art. 30, Codice del consumo arts. 46-49/52-59/128-130,
  DAC7) and prohibited_items add Italian specifics (art. 474 c.p.
  contraffazione, art. 648 c.p. ricettazione, legge 633/1941 artt.
  171-bis ss., D.Lgs. 30/2005).
- `db/seeds/legal/PT/pt/` — eight European-Portuguese templates:
  legal_notice cites DL 7/2004 art. 10 ({{legal_name}}, {{tax_id}} as
  NIPC, Conservatória do Registo Comercial {{registry}}) with a bracketed
  TODO for capital social; terms cover intermediary (DL 7/2004 arts.
  11-13 + DSA), ranking transparency, 18+, DSA complaints plus the
  Lei 144/2015 RAL route with an `[entidade RAL a indicar — TODO]`
  marker, the mandatory Livro de Reclamações Eletrónico
  (livroreclamacoes.pt, DL 74/2017), 0 % fees with 15-day notice,
  Portuguese law with the consumer's forum (art. 95.º-A CPC); privacy
  cites RGPD + Lei 58/2019, DAC7 via DL 41/2023 reporting to the AT,
  CNPD complaint (cnpd.pt); cookies cites Lei 41/2004 art. 5 (as
  amended by Lei 46/2012) + CNPD guidance (no cookie wall) with the
  shared cookie table; returns covers C2C (arts. 913 ss. CC route) vs
  B2C (14-day livre resolução, DL 24/2014 art. 10 with the annex-I
  formulário; garantia de conformidade 3 anos under DL 84/2021, used
  goods reducible by agreement to min. 18 months, presumption kept
  general "nos termos do DL 84/2021"); buyer_protection, seller_terms
  (traders: DSA art. 30, DL 24/2014 duties, Livro de Reclamações,
  DAC7) and prohibited_items (arts. 231-232 CP receptação/branqueamento,
  art. 296 CP contra a propriedade industrial). No EU ODR platform is
  mentioned in any text.
- Structural contract held for both sets: `# Title` first line, italic
  template note as first body line, 4+ `##` headings, only renderer-
  resolvable {{placeholders}}; bracketed TODO markers for the
  business-decision gaps (capitale sociale, PEC, entidade RAL, capital
  social).

**Why**

Completes the launch legal corpus for the IT and PT countries (launch
gate `Country#missing_legal_slugs` now empty for all six) and corrects a
wrong French conformity-presumption period.

**Files touched**: db/seeds/legal/FR/fr/returns.md;
db/seeds/legal/IT/it/*.md (8); db/seeds/legal/PT/pt/*.md (8);
.claude/context/history.md.

**Verification**: `bin/rails db:seed` ×2 (idempotent); runner check —
`missing_legal_slugs` empty for all 6 countries, LegalPage total 56
(IT 8, PT 8); `bin/rails test test/seeds/legal_pages_seeds_test.rb` 8
runs / 673 assertions / 0 failures; full `bin/rails test` 789 runs /
12479 assertions / 0 failures; `bin/rubocop` 427 files, no offenses.

## 2026-11-18 — Phase 7e: legal corpus for France (FR/fr) and Germany (DE/de)

**What changed**

- `db/seeds/legal/FR/fr/` — eight French templates adapted to French law
  (EU regulations kept): legal_notice cites LCEN art. 6-III identity
  disclosure ({{legal_name}}, {{registry}}, {{registered_address}},
  {{tax_id}}, RCS), directeur de publication and hébergeur as bracketed
  TODO markers; terms cite LCEN art. 6-I-2 + DSA notice-and-action /
  statement of reasons / complaints (arts. 16–17, 20–21, 23), ranking
  transparency via Reg. 2019/1150 + DSA art. 27 + Code de la consommation
  L111-7 (ranking criteria, pro-vs-private seller flag, consumer-law
  applicability), 18+, 0 % fees with 15-day notice, consommation mediator
  right (L612-1) with a `[médiateur de la consommation à désigner]`
  marker, French governing law; privacy cites RGPD + loi 78-17, DAC7 as
  CGI art. 1649 ter A (DGFiP reporting), CNIL complaint (cnil.fr), rights
  incl. post-mortem directives (art. 85 loi I&L); cookies cites art. 82
  loi I&L + CNIL guidelines (refusal as easy as acceptance, consent
  recommended valid 6 months, cookie lifetime 13 months) with the same
  strictly-necessary first-party cookie table as ES; returns covers C2C
  (no rétractation) vs B2C (14-day droit de rétractation, L221-18 s. and
  the R. 221-1 model form; garantie légale de conformité 2 years,
  reducible to 12 months for second-hand goods, 12-month presumption,
  L217-3 s.; garantie des vices cachés, C. civ. 1641 s.); seller_terms
  adds L111-7 display support, DSA art. 30 traceability and DAC7/CGI
  reporting; prohibited_items keeps the ES list plus contrefaçon under
  the Code de la propriété intellectuelle (L335-2, L716-4 s.).
- `db/seeds/legal/DE/de/` — eight German templates: legal_notice cites
  § 5 DDG (Name, Vertretungsberechtigte, Handelsregister {{registry}},
  USt-IdNr. {{tax_id}}) and § 18 Abs. 2 MStV with bracketed markers for
  the managing director and the content-responsible person; terms cover
  the intermediary role, DSA duties, ranking transparency via § 5b Abs.
  2 UWG + Reg. 2019/1150 + DSA art. 27 (plus § 5b Abs. 1 Nr. 6 UWG
  trader flag), 18+, 0 % fees with 15-day notice, the § 36 VSBG default
  non-participation statement with a confirm-before-publish marker,
  German law with habitual-residence consumer protections preserved;
  privacy cites DSGVO + BDSG, § 25 TDDDG (formerly TTDSG) for device
  access, PStTG/DAC7 reporting to the BZSt, supervisory-authority
  complaint; cookies cites § 25 TDDDG with the same necessary-cookie
  table; returns covers C2C (private warranty exclusion allowed) vs B2C
  (Widerruf §§ 312g, 355 BGB with the official model Widerrufsbelehrung
  and Muster-Widerrufsformular — Anlagen 1/2 EGBGB — as templates for
  traders; Gewährleistung 2 years § 438, used-goods reduction to 1 year
  § 476 Abs. 2 BGB, § 477 presumption); seller_terms adds trader
  Impressum/§ 18 MStV shop duties, PAngV gross-price-with-VAT and
  Grundpreis rules, DSA art. 30, PStTG/BZSt data; prohibited_items keeps
  the ES list plus § 86a StGB symbols, § 130 StGB / BpjM-indexed media
  and ProdSG/GPSR product safety.
- No ODR platform is mentioned anywhere (deliberately omitted). Only the
  allowed placeholders are used; the loader and the folder-driven seed
  test needed no changes — the new folders are picked up automatically.
  No commits (per instructions).

**Why**

FR and DE storefronts need day-one legal texts that reflect national
consumer, hosting and privacy law (LCEN/Code de la consommation + loi
I&L; DDG/UWG/BGB/VSBG/TDDDG/PStTG) on top of the directly applicable EU
regulations (GDPR, DSA, Reg. 2019/1150, DAC7); texts are originals, not
translations of the Spanish set.

**Files touched**: db/seeds/legal/FR/fr/*.md (8 new),
db/seeds/legal/DE/de/*.md (8 new).

**TODO markers inserted** (bracketed, template must be completed by the
operator before legal review): FR/fr/legal_notice.md
`[forme sociale et montant du capital social à compléter]`,
`[nom, prénom et qualité du directeur de la publication à compléter]`,
`[hébergeur à compléter — raison sociale, adresse et numéro de téléphone
de l'hébergeur]`; FR/fr/terms.md
`[médiateur de la consommation à désigner]`; DE/de/legal_notice.md
`[vertretungsberechtigte Geschäftsführung zu ergänzen]`,
`[verantwortliche Person i.S.d. § 18 Abs. 2 MStV zu ergänzen]`;
DE/de/terms.md `[Hinweis: Diese Erklärung nach § 36 VSBG ist vor
Veröffentlichung zu bestätigen; …]`.

**Gates**: `bin/rails db:seed` run twice (40 legal pages: ES/es 8,
ES/en 8, GB/en 8, FR/fr 8, DE/de 8; second run idempotent); legal seed
test 8 runs / 509 assertions 0 failures; `bin/rails test` 789 runs /
12315 assertions / 0 failures; `bin/rubocop` 427 files, no offenses.

## 2026-11-18 — Phase 7d: legal corpus for Spain-in-English (ES/en) and the United Kingdom (GB/en)

**What changed**

- `db/seeds/legal/ES/en/` — eight British-English translations of the ES/es
  templates (same slugs, same structure, Spanish law still governs; Spanish
  statutes keep their names with an English gloss on first use, e.g. TRLGDCU,
  LSSI-CE, LOPDGDD, AEAT/DAC7).
- `db/seeds/legal/GB/en/` — eight documents adapted to UK law (no EU-law
  citations): legal_notice uses the Electronic Commerce (EC Directive)
  Regulations 2002 reg. 6 + Companies Act 2006 identity disclosure
  ({{legal_name}}, {{registry}} as Companies House number, {{registered_address}},
  {{tax_id}} as VAT number); terms cover the intermediary role, 18+ accounts,
  pre-publication moderation, ranking parameters, Online Safety Act 2023
  user-to-user duties (illegal-content reports, complaints procedure,
  action on reports, appeals), suspension, direct-at-launch payments,
  0 % fees with 15-day notice, England & Wales governing law with Scottish
  and Northern Irish consumers keeping their local courts; privacy uses
  UK GDPR + DPA 2018, ICO complaint (ico.org.uk), IDTA/Addendum and
  adequacy regulations for transfers, and The Platform Operators (Due
  Diligence and Reporting Requirements) Regulations 2023 for HMRC seller
  reporting; cookies cites PECR 2003 + ICO guidance with the same
  strictly-necessary first-party cookie table; returns covers C2C (no
  statutory cancellation) vs B2C (CCRs 2013 14-day cancellation and refund,
  CRA 2015 satisfactory quality / fit for purpose / as described, 30-day
  short-term reject, repair/replacement, 6-month reversed burden of proof);
  seller_terms adds trader identification, the DMCC Act 2024 unfair
  commercial practices regime and HMRC reporting data; prohibited_items
  keeps the ES list plus UK-only illegality (Offensive Weapons Act 2019,
  Criminal Justice Act 1988 offensive weapons, Trade Marks Act 1994,
  UKCA/OPSS product safety) and OSA-based reporting.
- `test/seeds/legal_pages_seeds_test.rb` — two new tests derive the shipped
  country/locale sets from the filesystem and assert each set has exactly
  the 8 slugs on disk and in the DB, 4+ `##` headings, the italic template
  note as the body's first line, no placeholder outside
  `Setting.legal_identity.keys` (checked via `LegalPages::Render::PLACEHOLDER`),
  and renders with a 4+ entry TOC and no raw placeholders left.
- Only the allowed placeholders appear in the 16 new docs; the loader needed
  no changes. No commits (per instructions).

**Why**

English-speaking users on the Spain site need the same texts, and the GB
country needs a UK-law corpus from day one; the folder-driven test keeps
any future country/locale set honest.

**Files touched**: db/seeds/legal/ES/en/*.md (8 new),
db/seeds/legal/GB/en/*.md (8 new), test/seeds/legal_pages_seeds_test.rb.

**Gates**: `bin/rails db:seed` run twice (24 legal pages: ES/es 8, ES/en 8,
GB/en 8; second run idempotent); legal seed test 8 runs / 345 assertions
0 failures; `bin/rails test` 789 runs / 12151 assertions / 0 failures;
`bin/rubocop` 427 files, no offenses.

## 2026-11-18 — Phase 7c: Spanish legal templates (seeded), needs_legal_review flag, admin review workflow

**What changed**

- Migration `20261118030003` adds
  `legal_pages.needs_legal_review` (boolean, NOT NULL, default true) — every
  seeded legal text is a TEMPLATE until legal counsel signs it off.
- `LegalPage`: `pending_legal_review` scope (published AND needs_legal_review)
  + virtual `legal_reviewed` (inverse of needs_legal_review) for the admin
  checkbox.
- Admin legal pages: index rows and edit header show an amber
  "Template — pending legal review" chip while true; the form gained a
  "Reviewed by legal counsel" checkbox (`legal_page[legal_reviewed]`,
  permitted; ticking it sets needs_legal_review=false) and the update audit
  row now records `needs_legal_review`. Dashboard: `DashboardStats` gained
  `legal_pages_pending_review` (published pages still pending) shown as a
  footnote on the admin dashboard.
- Seed loader `db/seeds/legal_pages.rb` (loaded from `db/seeds.rb` after
  labels_seller_tags): upserts `db/seeds/legal/<COUNTRY>/<locale>/<slug>.md`
  by (country_code, locale, slug) — first line `# Title` → title, rest →
  body, published: true, needs_legal_review: true. **NEVER overwrites a page
  whose needs_legal_review is false** (admin-approved text wins; logs a
  skip). Idempotent; malformed paths are warned and skipped.
- 8 Spanish templates in `db/seeds/legal/ES/es/`: terms, privacy, cookies,
  legal_notice, returns, buyer_protection, seller_terms, prohibited_items.
  Accurate for Spain/EU (LSSI-CE arts. 10/16/22.2, RGPD+LOPDGDD, DSA arts.
  11–12/16/17/20/21/23/27/30, Reg. 2019/1150 ranking transparency, TRLGDCU
  arts. 102–108 withdrawal + art. 120 guarantee 3y/≥1y used per RDL 7/2021,
  DAC7 Directive 2021/514 transposed by Ley 13/2023 → AEAT reporting when
  payments run through the platform, AEPD complaint right). NO EU ODR
  mention (discontinued 2025). Each doc starts with an italic
  "pending legal review" note, uses only the identity placeholders
  ({{site_name}} {{legal_name}} {{tax_id}} {{registered_address}}
  {{registry}} {{contact_email}} {{dpo_email}}) and has ≥4 `##` headings
  (TOC). Company data never invented.
- Locale keys ×6: `admin.legal_pages.{index,edit}.pending_review_chip`,
  `admin.legal_pages.form.{reviewed,reviewed_hint}`,
  `admin.dashboards.show.footnote.legal_pending_review` (one/other).

**Tests**: new `test/seeds/legal_pages_seeds_test.rb` (all 8 ES/es seeded
pending review, title/body split, idempotent re-run, reviewed pages never
overwritten, ≥4 headings + TOC, no unresolved `{{…}}` after render with
identity Settings). `Admin::LegalPagesControllerTest`: chip shows/hides,
"Reviewed by legal counsel" PATCH clears needs_legal_review + audited
(details include it), checkbox rendered. `Admin::DashboardStatsTest`:
pending-review count. `CountryTest`: enabling checks the country DEFAULT
locale (English-only pages don't satisfy GB). Full suite 787 runs / 11905
assertions green; rubocop clean; locale lint 2570 keys ×6; zeitwerk +
eager_load OK; dev curl: all 8 `/es/legal/<slug>` → 200, 0 unresolved
placeholders.

**Files touched**: db/migrate/20261118030003*.rb; app/models/legal_page.rb;
app/controllers/admin/legal_pages_controller.rb;
app/views/admin/legal_pages/{index,edit,_form}.html.erb;
app/services/admin/dashboard_stats.rb; app/views/admin/dashboards/show.html.erb;
db/seeds.rb + db/seeds/legal_pages.rb; db/seeds/legal/ES/es/*.md (8);
config/locales/{es,en,fr,de,it,pt}.yml;
test/seeds/legal_pages_seeds_test.rb, test/controllers/admin/legal_pages_controller_test.rb,
test/services/admin/dashboard_stats_test.rb, test/models/country_test.rb.

## 2026-11-18 — Phase 7b: trust & safety page, content pages, contact inbox, listing reports, public legal delivery, cookie consent, footer rebuild

**What changed**

- Migrations: `20261118030001` (`contact_messages`: name/email/subject/body,
  `locale` string, index on created_at), `20261118030002` (`reports`:
  listing/user FKs, `reason` enum scam/prohibited/wrong_info/offensive/other,
  `details`, `resolved_at/resolved_action/resolved_by_id`, + **partial unique
  index on (listing_id, user_id) WHERE resolved_at IS NULL** — one open
  report per user per listing at the DB level).
- **Static content pages**: `PagesController#show` (`/pages/:slug`) with a
  `PAGE_SLUGS` whitelist (about, how-it-works, selling, help, contact,
  seller-guides) — unknown slugs 404, no Page model; all copy from I18n
  (`pages.<underscored_slug>.*`). New templates `pages/{about,how_it_works,
  selling,help,contact,seller_guides}.html.erb`. The contact page embeds the
  form posting to `contact_messages_path`.
- **Contact messages**: `ContactMessage` (name, email, subject 1..140,
  body 10..5000, `locale` captured from the request, `recent` scope).
  `ContactMessagesController#create` (unauthenticated, `rate_limit to: 5,
  within: 30.minutes`) stores the row, enqueues `ContactMailer#received`
  (→ `Setting "support_email"`, recipient locale) and redirects back with
  `contact_messages.create.{created,invalid,rate_limited}` flashes. Admin
  read-only inbox: `Admin::ContactMessagesController` index (pagy 25,
  **locale filter param is `lang`** — `locale` is the routing segment) +
  show (full body + metadata).
- **Listing reports**: signed-in `ReportsController#new/#create` nested
  under listings; "Report this listing" link on `listings/show` now points
  at `new_listing_report_path`. `Report` model: reason enum, open/closed
  by `resolved_at`, `close!(action, admin:)` (arg validated FIRST, then
  `Report::InvalidTransition` on double-close), `not_own_listing` +
  `no_open_duplicate` (custom validation adding `:already_reported` to
  `:user_id` — see gotchas), `FLOOD_THRESHOLD = 3`: the 3rd concurrent
  OPEN report on a live listing re-enters moderation (`request_revalidation!`)
  and `after_create_commit` e-mails all admins (`ReportMailer#listing_flagged`,
  per-admin locale). Admin inbox `Admin::ReportsController` (state/reason
  filters, open-first ordering) + closing via nested singular resources
  `report_resolutions` (resolve = acted on listing) / `report_dismissals`
  — both audited (`audit!`), sidebar entries for Reports and Contact
  messages.
- **Public legal pages**: `LegalPagesController#show` `/legal/:slug` —
  resolution chain request locale → `en` → `Country.default_locale`
  (`LegalPage.find_public`); renders through `LegalPages::Render`
  (`app/services/legal_pages/`): `{{legal_name}}`-style placeholders from
  `Setting.legal_identity`, Commonmarker markdown → allowlisted sanitizer
  (`LegalPagesHelper#legal_markdown`), TOC. Footer legal column lists only
  slugs that actually deliver for the country (`LegalPage.deliverable_slugs`,
  one query).
- **Trust & Safety**: `/trust-and-safety` (`TrustsController#show`) — live
  counts from `Trust::Stats.visible`, each stat hidden below
  `Setting "min_public_stat"` (default 50); safeguards grid + support
  contact block (email/phone from Settings). Trust links added to
  cart/checkout footers and the listing-show protection line.
- **Cookie consent (GDPR)**: `layouts/_footer` hosts `shared/_cookie_consent`
  (Stimulus `cookie_consent_controller.js`); preferences stored in the
  `cookie_consent` cookie as URL-encoded JSON `{version, categories,
  timestamp}` — "necessary" implicit, `analytics` optional; `CONSENT_VERSION = 1`
  in `ApplicationController` (bump it to re-banner everyone). Helpers
  `cookie_consent?`/`cookie_consent_needed?`/`cookie_consent_version`.
  No analytics scripts exist yet, so accepting/rejecting only writes the
  cookie — covered by `test/controllers/cookie_consent_test.rb`.
- **Footer rebuilt**: link columns (about/trust/blog; help/contact/support
  email + phone; legal column; social links; language switcher; newsletter
  form kept) — all Settings read in ONE `Setting.get_many(FOOTER_KEYS)`.
- **Legal identity in settings**: `Admin::Settings` spec gained
  `legal_name/trade_name/tax_id/registered_address/mercantile_registry_data/
  contact_email/dpo_email/phone` (+ `social_links`, `blog_url`); dashboard
  shows a "legal identity incomplete" banner driven by
  `Setting.legal_identity_complete?`. `Setting` model: `get_many(keys)`
  (single query for cache misses, misses still NOT cached), `IDENTITY_KEYS`
  + `FOOTER_KEYS`, `legal_identity(values = nil)` (accepts pre-batched
  values — the footer reuses one read), `DEFAULTS` + `min_public_stat`
  (seeded settings 5 → 6).

**Gotchas / pre-existing bugs fixed along the way**

- **`params[:locale]` is reserved** by the `scope "(:locale)"` routing
  segment: any URL carrying `?locale=xx` is matched against the segment and
  404s for unknown locales. The admin contact-inbox filter therefore uses
  `lang` (controller + view + tests aligned).
- **Rails 8.1 `uniqueness` validator always reports `:taken`** in
  `errors.details` (activerecord 8.1 `uniqueness.rb`) — callers/tests that
  key off a custom symbol (`:already_reported`) need a custom validation;
  the partial unique index still backstops race conditions.
- **`sanitize` is an ActionView helper**: plain service objects mixing the
  helper module get NoMethodError on the class-level sanitizer — call
  `Rails::HTML5::SafeListSanitizer.new.sanitize(...)` explicitly; its
  result is an UNSAFE String → `<%= %>` escapes it (admin legal preview
  showed literal tags until `.html_safe` was added inside `legal_markdown`).
- Parameterized mailers must be invoked as `Mailer.with(...).action` —
  several call sites still used the old zero-arg style.
- `Report#close!` validates the action argument BEFORE the open? guard so
  a typo on a closed report raises `ArgumentError`, not `InvalidTransition`.
- Two locale texts were byte-identical (`trusts.show.safeguards.verified.title`
  vs `stats.verified_sellers`), breaking a "label not contained in" assertion
  — the safeguard title was reworded in all 6 files.
- Lazy-lookup locale keys must sit under the action scope the controller
  uses (`contact_messages.create.rate_limited`; admin resolution/dismissal
  flash keys under their own controller scopes).

**Pre-existing tests adjusted**

- `test/seeds/reference_data_test.rb`: seeded settings 5 → 6
  (`min_public_stat` default).
- `test/controllers/admin/reports_controller_test.rb`: "index filters by
  state and reason" was self-contradictory (asserted an EMPTY page after
  filtering by the state the seeded report has) → rewritten to assert the
  closed report is visible under `state=closed` and hidden under `open`,
  reason filtering, and the empty-state message.
- `test/controllers/admin/access_test.rb`: added `access_report` /
  `access_contact_message` helpers so the shared access matrix covers the
  two new admin resources.
- `test/controllers/listings_controller_test.rb` N+1 guard (≤24 queries on
  the index) forced the footer/identity batching above: layout Setting reads
  went from one-query-per-key to two batched reads (footer `FOOTER_KEYS` +
  `maintenance_mode`).

**New tests**: `test/models/{contact_message,report}_test.rb`,
`test/controllers/{contact_messages,admin/contact_messages,reports,
admin/reports,legal_pages,trusts}_controller_test.rb`,
`test/controllers/cookie_consent_test.rb`,
`test/controllers/admin/dashboards_controller_test.rb` (legal banner);
`admin/access_test.rb` extended. Suite: **776 runs / 11 779 assertions**
green; locale tree now **2564 keys** ×6.

## 2026-11-18 — Phase 7a: PC Finder, performance scoring & sell-to-us trade-ins (flag `sell_to_us`)

**What changed**

- **Performance scoring**: `Performance::Scorer` (`app/services/performance/`)
  turns the free-text `gpu_model`/`cpu_model` listing specs into a 0–1000
  `listings.performance_score` from tier tables `config/data/gpu_tiers.yml` +
  `cpu_tiers.yml` (model names fuzzy-normalized: brand words and laptop/mobile
  suffixes dropped, punctuation stripped; 75% GPU + 25% CPU, weights
  re-normalized when only one resolves, **nil** when neither matches — never a
  fake score). Only `Listing::SCORABLE_CATEGORY_SLUGS` (gaming-pcs,
  workstations, laptops + descendants) score, via `Listing#scorable_category?`
  (public for the rake task) + `refresh_performance_score` before_save.
  Column existed since Phase 1; migration `20261118020002` adds a partial
  index (`WHERE performance_score IS NOT NULL`). Backfill: `bin/rails
  performance:backfill` (deliberate `update_column`). Dev after seeding:
  **4 of 46 listings scored** (383/498/560/838 — same numbers the test
  fixtures pin). `Performance::FpsEstimator` maps score → estimated FPS per
  game from `config/data/games.yml` (per-game `required_score` per
  resolution/FPS target); `estimate` clamps input to `SCORE_CAP = 1000`
  because extrapolation slopes cross and invert above the tier scale.
  UI: `shared/_performance_bar` in listing cards + `listings/show` score/FPS
  block.
- **PC Finder**: `/pc-finder` quiz (`PcFindersController#show`, Stimulus
  `quiz_controller.js`, progressive-enhanced GET form) → results page
  `/pc-finder/results` (`PcFinderResultsController#index`). `PcFinder::Search`
  builds on ListingSearch-era patterns but its own query: gaming-pcs subtree,
  budget bands, chosen seller tags AND-ed, and a score floor = **max** of the
  selected games' `required_score` at the chosen resolution×FPS; ordered by
  **value = performance_score / price** (unscored fall to 0 and sink), 9 per
  page, "best match" badge, pagy "Load more" turbo frame.
  `PcFinder::Search.sample_for(game_slug)` feeds the `pages/home/_finder`
  strip. Both controllers `allow_unauthenticated_access`.
- **Sell-to-us trade-ins** behind Flipper `:sell_to_us` (public controllers
  `head :not_found` while off): `TradeIn` model (migration `20261118020001`) —
  `component_type` gpu/cpu, 4 conditions, status enum
  `quoted/accepted/received/inspected/paid/rejected/expired` + `TRANSITIONS`
  map, `transition_to!`/`expire!` raising `TradeIn::InvalidTransition`,
  `QUOTE_TTL` 7 days. Public flow `/sell-to-us` (`TradeInQuotesController`
  new/create/show) → `TradeIns::Quote` prices from
  `config/data/trade_in_prices.yml`; sign-in + accept
  (`TradeInAcceptancesController` → `TradeIns::Accept`, stale quotes
  refused). Admin shipment walk: `Admin::TradeInsController`
  (index/show/audited `update` via `transition_to!`) + sidebar entry.
- **Dev seed**: `db/seeds/sample_listings.rb` gained 4 gaming PCs in the
  gaming-pcs subtree (`value-pcs`/`mid-range-pcs`/`pro-gamer-pcs`) carrying
  `gpu_model`/`cpu_model` specs + finder-relevant seller tags
  (`air-cooling`/`aio-cooling`/`competitive` added to `seller_tags.yml`), and
  per-sample `tags:` support in the loader.

**Pre-existing bugs fixed along the way**

- `layouts/_header.html.erb` cart link rendered broken (`link_to cart_path,
  class:` — text arg missing since Phase 6a) → `link_to t("nav.cart"), …`.
- PC Finder locale scopes `_result:`/`_page:` never resolved: partial lazy
  lookup searches for `pc_finder_results.result.*` (leading underscore is
  stripped from the lookup, not part of it). Renamed to `result:`/`page:` in
  all 6 locale files + new `pc_finder_results.index.title` with an `<h1>`.
- Custom `TradeIn#expired?` shadowed the status-enum predicate, so the show
  view's `expired?` branch died → removed; wall-clock staleness is
  `stale_quote?` (`quoted? && expires_at <= Time.current`), used by
  `TradeIns::Accept`, `TradeInQuotesController#show` and
  `Admin::TradeInsController#show`.
- `performance:backfill` called non-existent
  `Performance::Scorer.score_for_listing`; `Listing#scorable_category?` was
  private → made public.
- Sample seed wrote autonomous-community names into `listings.region`, which
  fails `Listing#region_known` (validates **province** names via `EsProvince`)
  — latent because the dev rows predated the validation; sample sellers now
  carry `province:` and the existing dev rows were normalized.

**Pre-existing tests adjusted (fixture-count shifts / contradictions)**

- `test/services/listing_search_test.rb`: expectations rewritten for the 4
  new gaming-PC fixtures (7 approved listings; q=rtx 5; price/condition
  counts; facet maps; seller_tag counts; `spec_facets` now includes
  cpu_model/gpu_model — those fixture specs are TEXT specs so
  `facet_attributes` stays `negotiable ports vram`).
- `test/controllers/listings_controller_test.rb`: index h3 3→7, search
  h3 3→5.
- `test/services/sell/dashboard_stats_test.rb`: live_listings 1→3;
  top_listings made deterministic (views 120/80).
- `test/seeds/reference_data_test.rb`: created counts 61→60 categories,
  34→32 spec attributes, 88→86 attachments, 24→21 seller tags (gaming-pcs,
  gpu_model/cpu_model, competitive/air-cooling/aio-cooling pre-exist in
  fixtures).
- `test/integration/trade_in_test.rb`: "another user cannot steal a claimed
  quote" was self-contradictory (the anonymous quote IS legitimately
  claimable by the second user) → success expectations; flag-off test
  extended with show + acceptance 404 asserts.
- `test/integration/pc_finder_test.rb`: `_result.best_match` key ref →
  `result.best_match`.

**New tests**: `test/services/performance/{scorer,fps_estimator}_test.rb`,
`test/services/pc_finder/search_test.rb`, `test/integration/{pc_finder,trade_in}_test.rb`,
`test/controllers/admin/trade_ins_test.rb`; fixtures: 4 gaming PCs
(+`listing_tags`), `gaming-pcs`/`gaming-desktops` categories,
`cpu_model`/`gpu_model` spec attributes (+category attachments), seller
tags. Suite: 707 runs / 11 434 assertions green; locale tree now **2153
keys** ×6.

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
