ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Fixture inserts bypass the listings_tsv trigger, so keyword search would
    # see empty vectors without this.
    setup { Listing.reindex_search_vectors! }
  end
end

# All routes live under an optional /(:locale) segment. Integration test URL
# helpers merge this into url_options, so every helper-built path is /en/...
# and positional segment args (e.g. password_path(token)) bind to the right
# key. :en keeps the generated auth tests' English flash assertions working
# (the app default locale is :es).
Rails.application.routes.default_url_options[:locale] = :en

# Tests assert English validation/error messages; the app default locale is :es.
# Tests that need Spanish wrap themselves in I18n.with_locale(:es).
I18n.default_locale = :en
