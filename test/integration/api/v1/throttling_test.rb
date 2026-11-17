require "test_helper"

module Api
  module V1
    # Throttles, the Accept-Language contract and the bearer-auth direct
    # upload handshake. The test cache is a memory store, so the rate limits
    # really run; each throttle test uses its own client IP to stay isolated.
    class ThrottlingTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
      end

      test "the sign-in throttle answers with the same envelope" do
        env = { "REMOTE_ADDR" => "10.0.0.9" }
        headers = json_api_headers(user: nil).merge("CONTENT_TYPE" => "application/json")

        statuses = 11.times.map do
          post "/api/v1/session",
               params: { email_address: @user.email_address, password: "wrong" }.to_json,
               headers: headers, env: env
          response.status
        end

        assert_equal [ 401 ] * 10 + [ 429 ], statuses

        error = json_body[:error]
        assert_equal "rate_limited", error[:code]
        assert_not error[:message].blank?
      end

      test "Accept-Language picks the language of error messages" do
        get_json "/api/v1/me", auth_as: nil,
                               headers: json_api_headers(user: nil).merge("Accept-Language" => "fr;q=0.9,es;q=0.8")

        assert_response :unauthorized
        assert_equal I18n.t("api.errors.unauthorized", locale: :fr), json_body.dig(:error, :message)

        get_json "/api/v1/me", auth_as: nil, headers: json_api_headers(user: nil)
        assert_response :unauthorized
        assert_equal I18n.t("api.errors.unauthorized", locale: I18n.default_locale),
                     json_body.dig(:error, :message)
      end

      test "unsupported languages fall back to the default locale" do
        get_json "/api/v1/me", auth_as: nil,
                               headers: json_api_headers(user: nil).merge("Accept-Language" => "nl,en-US")

        assert_equal I18n.t("api.errors.unauthorized", locale: :en), json_body.dig(:error, :message)
      end

      test "direct uploads hand back a signed id for the listing form" do
        bytes = "photo-bytes"
        post_json "/api/v1/direct_uploads", {
          blob: {
            filename: "gpu.jpg", byte_size: bytes.bytesize, content_type: "image/jpeg",
            checksum: Base64.strict_encode64(Digest::SHA1.digest(bytes)), metadata: {}
          }
        }, auth_as: @user

        assert_response :created
        body = json_body
        assert_not body[:signed_id].blank?
        assert_not body.dig(:direct_upload, :url).blank?
        assert_kind_of Hash, body[:direct_upload][:headers]
      end

      test "a direct upload without a blob param is a 400 envelope" do
        post_json "/api/v1/direct_uploads", {}, auth_as: @user

        assert_response :bad_request
        assert_equal "invalid_request", json_body.dig(:error, :code)
        assert_equal "blob", json_body.dig(:error, :details, :param)
      end
    end
  end
end
