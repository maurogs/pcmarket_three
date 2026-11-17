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

# Development-only catalogue so the browse pages have something to show.
# The loader itself is a no-op outside development and test.
load seed_dir.join("sample_listings.rb")
