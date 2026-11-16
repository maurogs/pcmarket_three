# Flipper feature flags, stored in PostgreSQL (flipper_features / flipper_gates).
#
# Phase 0 flags (all OFF by default — enable them explicitly with Flipper.enable):
#   commissions, featured_listings, stripe_checkout, sell_to_us, google_login
#
# Usage: Flipper.enabled?(:stripe_checkout, current_user)
require "flipper"
require "flipper/adapters/active_record"

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end
