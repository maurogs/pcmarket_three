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
