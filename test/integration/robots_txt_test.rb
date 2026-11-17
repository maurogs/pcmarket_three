require "test_helper"

# Phase 8a: dynamic robots.txt (Setting.search_engine_indexing + env).
class RobotsTxtTest < ActionDispatch::IntegrationTest
  # Swap the memoized Rails.env (RAILS_ENV is "test" here) for the block.
  def in_production
    original = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    yield
  ensure
    Rails.instance_variable_set(:@_env, original)
  end
  test "crawlers are disallowed outside production" do
    get "/robots.txt"
    assert_response :success
    assert_match %r{^Disallow: /$}m, response.body
    assert_no_match(/Sitemap:/, response.body)
  end

  test "production stays closed while search_engine_indexing is off" do
    Setting.set("search_engine_indexing", false)
    in_production do
      get "/robots.txt"
    end
    assert_match %r{^Disallow: /$}m, response.body
  end

  test "production opens up when search_engine_indexing is on" do
    Setting.set("search_engine_indexing", true)
    in_production do
      get "/robots.txt"
    end
    assert_no_match %r{^Disallow: /$}m, response.body
    %w[/admin /sell /account /cart /checkout].each do |path|
      assert_includes response.body, "Disallow: #{path}"
    end
    assert_match %r{^Sitemap: http://www.example.com/sitemaps/sitemap\.xml\.gz$}, response.body
  end
end
