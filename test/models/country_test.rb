require "test_helper"

class CountryTest < ActiveSupport::TestCase
  test "seed_defaults! is idempotent" do
    Country.delete_all
    assert_difference -> { Country.count }, Country::DEFAULTS.size do
      Country.seed_defaults!
    end
    assert_no_difference -> { Country.count } do
      Country.seed_defaults!
    end
  end

  test "only spain is enabled by default" do
    Country.delete_all
    Country.seed_defaults!
    assert_equal [ "ES" ], Country.enabled.pluck(:code)
  end

  test "display_name resolves the i18n key" do
    I18n.with_locale(:es) do
      assert_equal countries(:es).display_name, I18n.t("countries.es")
    end
  end
end
