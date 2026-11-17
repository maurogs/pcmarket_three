# Launch countries and platform settings. Country.seed_defaults! and
# Setting.seed_defaults! upsert by code/key (models are the single source
# of truth for these defaults), so this loader is idempotent.
Country.seed_defaults!
Setting.seed_defaults!

# Register every known feature flag (defaults OFF) so the admin flags page
# and any enable/disable calls never hit unknown-feature adapter warnings.
FeatureFlags.register_all!
