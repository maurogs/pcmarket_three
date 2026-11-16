require "test_helper"

class SettingTest < ActiveSupport::TestCase
  setup do
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @cache
  end

  test "get returns default when missing" do
    assert_equal "PCMarket", Setting.get("site_name", "PCMarket")
  end

  test "set then get returns the value" do
    Setting.set("site_name", "PCMarket Local")
    assert_equal "PCMarket Local", Setting.get("site_name")
  end

  test "get caches the value and set invalidates it" do
    Setting.set("site_name", "One")
    assert_equal "One", Setting.get("site_name")

    Setting.where(key: "site_name").find_each { |row| row.update_columns(value: "Stale") }
    assert_equal "One", Setting.get("site_name") # served from cache

    Setting.set("site_name", "Two")
    assert_equal "Two", Setting.get("site_name")
  end

  test "seed_defaults! is idempotent" do
    assert_difference -> { Setting.count }, Setting::DEFAULTS.size do
      2.times { Setting.seed_defaults! }
    end
    assert_equal "PCMarket", Setting.get("site_name")
  end
end
