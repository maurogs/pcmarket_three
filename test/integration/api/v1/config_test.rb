require "test_helper"

module Api
  module V1
    # GET /api/v1/config — the first-launch bundle for native clients:
    # pickers, localized labels, web URLs and the feature-flag booleans.
    class ConfigTest < ActionDispatch::IntegrationTest
      test "config returns the pickers the apps need" do
        get_json "/api/v1/config"

        assert_response :ok
        body = json_body
        assert_includes body[:categories].map { |c| c[:slug] }, "graphics-cards"
        assert body[:categories].any? { |c| !c[:parent_id].nil? }
        assert_includes body[:conditions], "brand_new"
        assert_includes body[:carriers], "Correos"
        assert_includes body[:order_statuses], "paid"
        assert body[:web_urls].key?(:home)
        assert body.key?(:min_app_version)
      end

      test "flags exposes every registry feature as a boolean" do
        get_json "/api/v1/config"

        assert_response :ok
        flags = json_body[:flags]
        assert_equal FeatureFlags::FEATURES.keys.map(&:to_sym).sort, flags.keys.sort
        flags.each_value { |value| assert_includes [ true, false ], value }
      end

      test "a switched-on flag comes back true" do
        Flipper.enable("sell_to_us")
        begin
          get_json "/api/v1/config"
          assert_equal true, json_body.dig(:flags, :sell_to_us)
        ensure
          Flipper.disable("sell_to_us")
        end
      end

      test "config is cacheable with an etag" do
        get_json "/api/v1/config"
        etag = response.headers["ETag"]
        assert_not etag.blank?

        get_json "/api/v1/config", headers: { "If-None-Match" => etag }
        assert_response :not_modified
      end
    end
  end
end
