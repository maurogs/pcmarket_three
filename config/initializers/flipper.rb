# Flipper feature flags, stored in PostgreSQL (flipper_features / flipper_gates).
#
# FEATURES is the registry the admin flags page (Phase 6b) renders: one
# entry per known flag with its description i18n key and an optional
# `warning` — a soft warning the form shows when the flag is switched on
# without its prerequisites (never blocks the toggle).
#
# Usage: Flipper.enabled?(:stripe_checkout, current_user)
require "flipper"
require "flipper/adapters/active_record"

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end

module FeatureFlags
  FEATURES = {
    "commissions" => {
      description_key: "admin.feature_flags.flags.commissions.description",
      warning: "commission_percent_zero"
    },
    "featured_listings" => {
      description_key: "admin.feature_flags.flags.featured_listings.description",
      warning: nil
    },
    "stripe_checkout" => {
      description_key: "admin.feature_flags.flags.stripe_checkout.description",
      warning: "missing_stripe_env"
    },
    "sell_to_us" => {
      description_key: "admin.feature_flags.flags.sell_to_us.description",
      warning: nil
    },
    "google_login" => {
      description_key: "admin.feature_flags.flags.google_login.description",
      warning: nil
    }
  }.freeze

  # Soft warning text for a flag state (nil = nothing to show).
  def self.warning_for(key, enabled:)
    warning = FEATURES.fetch(key).fetch(:warning)
    return nil if warning.nil? || !enabled

    case warning
    when "missing_stripe_env"
      return nil if ENV["STRIPE_SECRET_KEY"].present? && ENV["STRIPE_WEBHOOK_SECRET"].present?

      I18n.t("admin.feature_flags.warnings.missing_stripe_env")
    when "commission_percent_zero"
      return nil if Setting.get("commission_percent").to_f.positive?

      I18n.t("admin.feature_flags.warnings.commission_percent_zero")
    end
  end

  # Registers every known feature with Flipper (boolean gate OFF) so the
  # flags exist in the adapter and neither reads nor disables log
  # "Could not find feature" warnings. Flipper.add just stores a false
  # boolean gate, so calling it repeatedly is safe (never enables).
  def self.register_all!
    FEATURES.each_key { |key| Flipper.add(key) }
  end
end
