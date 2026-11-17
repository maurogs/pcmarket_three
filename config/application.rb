require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AppTestThree
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # I18n: Spanish-first marketplace, English fallback (see config/locales/*.yml).
    config.i18n.available_locales = %i[es en fr de it pt]
    config.i18n.default_locale = :es
    config.i18n.fallbacks = [ :en ]

    # Rails 8.1 defaults variants to libvips, which is not installed here:
    # the transformer stays nil and every variant render raises. ImageMagick
    # + mini_magick (both available) process the gallery variants instead.
    config.active_storage.variant_processor = :mini_magick
  end
end
