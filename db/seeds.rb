# Reference-data seeds (Phase 2a: taxonomy, filters, labels, tags; later
# phases add more loaders under db/seeds/). Every loader upserts by stable
# slug/key, so `bin/rails db:seed` is idempotent and safe at any time in
# every environment. Raw data lives in db/seeds/data/*.yml for the admin
# team; loaders run in the order below.
seed_dir = Rails.root.join("db", "seeds")

# support file is a plain module definition, so `require` (loaded once);
# the loaders below are re-`load`ed on every run.
require seed_dir.join("support/seed_loader.rb").to_s

%w[
  countries_settings
  categories
  spec_attributes
  labels_seller_tags
  legal_pages
].each { |name| load seed_dir.join("#{name}.rb") }

# Development-only realistic demo data (PHASE 9): stores, listings with real
# photos, and a full social/commerce graph. DemoSeed.run! is gated inside
# db/seeds/demo.rb too (never production, never test); the demo catalogue
# lives in db/seeds/data/demo_catalog.yml. See README "Demo data".
require seed_dir.join("demo.rb").to_s
DemoSeed.run! if Rails.env.development? || ENV["SEED_DEMO"] == "1"
