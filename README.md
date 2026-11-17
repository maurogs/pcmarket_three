# PCMarket

A Spanish second-hand marketplace for PC hardware, built with Rails 8.1
(Ruby 4.0, PostgreSQL, Hotwire/Vite). Bilingual public catalog (6 locales),
seller stores, offers, messaging, carts/orders with a Spanish-fulfilment
state machine, moderation, an admin panel and a JSON API v1.

## Getting started

```sh
bin/setup          # create DB, load reference data, run migrations
bin/rails server   # http://localhost:3000
```

Reference data (categories, spec attributes, labels, legal pages, countries)
is idempotent and always loaded by `bin/rails db:seed`.

## Demo data

`db/seeds/demo.rb` (`DemoSeed`) fills the development database with a
realistic Spanish marketplace dataset — listings with **real product photos**,
seller stores with logos, offers, conversations, orders in every lifecycle
state, reviews and more. It is refused in production unless
`ALLOW_DEMO_SEED=1`.

```sh
bin/rails db:seed                    # dev: reference data + 300 demo listings
SEED_LISTINGS=50 bin/rails db:seed   # fewer listings
SEED_RESET=1 bin/rails db:seed       # wipe demo rows first, then re-seed
SEED_SEED=42 bin/rails db:seed       # reproducible randomness
```

Key facts:

- **Idempotent** — demo users use fixed `*@demo.pcmarket.test` e-mails and a
  second run tops up to the target instead of duplicating. Running the seed
  twice leaves exactly `SEED_LISTINGS` listings.
- **Photos come from real image APIs** (`app/services/demo_images/`):
  Openverse works with no API key; Pexels and Pixabay activate when
  `PEXELS_API_KEY` / `PIXABAY_API_KEY` are set. Results are cached under
  `tmp/demo_images/` (delete that folder to re-fetch). If every provider
  fails (or the machine is offline) ImageMagick-generated placeholders are
  used instead, so seeding never needs network access to succeed.
  Unsplash is deliberately not used: its API requires render-time source
  loads that are incompatible with one-time seed downloads.
- **Attribution is preserved** — each photo's creator, license and source
  URL are stored in the blob's metadata and shown under the listing gallery
  ("Foto: … · CC BY-SA vía openverse").
- **Test accounts** — every demo user's password is `DemoPassw0rd!`:
  `admin@demo.pcmarket.test` (admin), `business1-8@demo.pcmarket.test` (verified stores with valid CIFs),
  `seller1-40@…`, `buyer1-60@…`.

## Tests & quality gates

```sh
bin/rails test          # Minitest; webmock blocks real HTTP in tests
bin/rubocop
ruby script/lint_locale_keys.rb
```

## Performance

**Caching layers**

- **Fragment cache** — the heavy partials (listing cards, header mega menu,
  footer, category nav) are Rails fragments keyed on locale + record
  `updated_at` busting, stored in **Solid Cache** (`cache/production` database)
  in production; `Rails.cache.clear` on category changes.
- **HTTP caching is browser-only for HTML** — `BrowserCaching`
  (`app/controllers/concerns/browser_caching.rb`) sends
  `Cache-Control: private, max-age=0, must-revalidate` on 200 responses for
  the catalog pages (category, listings index, PC-finder results), and the
  listing/store conditional-GET headers pass `public: false`. HTML pages are
  never `public` because even anonymous pages embed per-session data — the
  CSRF meta token and the guest cart badge — so a CDN or shared cache must
  not store them; a CDN should only cache static assets, Active Storage
  variants and `/sitemaps`.
- **Conditional GET** — listing and store pages emit an `ETag` derived from
  `updated_at` (plus locale, signed-in flag and guest-cart state, so a 304
  can never return a stale cart badge); repeat visitors get a 304 with no
  body. The JSON API sends ETags on collection endpoints too.
- **Preprocessed Active Storage variants** — card images (400w/800w WebP) are
  generated at upload time (`preprocessed: true`) and their URLs are cached;
  the `<img>` tags ship `srcset` + `sizes` so phones download the 400px file.

**Measuring & N+1 detection**

- `bin/rails runner script/perf_baseline.rb <label>` fetches every key page
  twice (cold + warm) with caching enabled and prints per-page status, wall
  time, query count and SQL time — output lands in `tmp/perf/`.
- **Prosopite** (`group :development, :test`) raises on any N+1 during tests,
  so regressions fail CI rather than shipping.

**Tuning for production**

- `WEB_CONCURRENCY` (Puma workers) and `RAILS_MAX_THREADS` are read from the
  environment by `config/puma.rb`; keep workers × threads in step with the
  database's `POOL` (`.env` default `POOL=5`).
- YJIT is enabled in production via `config/initializers/yjit.rb` — it is a
  no-op unless the Ruby build has YJIT, so build the deploy image with
  `--enable-yjit`.
- Point a CDN in front of the app for the anonymous catalog pages; the
  `stale-while-revalidate=300` window means stale copies are served while the
  origin refreshes, which hides origin latency spikes.
