require "test_helper"

module Api
  module V1
    # Sign-in issues a bearer token, /me reads it back, and revocation kills
    # it immediately. Banned accounts are refused at sign-in, and every
    # unauthenticated call gets the same error envelope.
    class AuthTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
      end

      test "sign-in returns a bearer token and the user" do
        post_json "/api/v1/session", params: { email_address: @user.email_address, password: "password" }

        assert_response :ok
        body = json_body
        assert_match(/\A[A-Za-z0-9]{32}\z/, body[:token].to_s)
        assert_equal @user.email_address, body[:email_address]

        use_token @user, body[:token]
        get_json "/api/v1/me"
        assert_response :ok
        assert_equal @user.display_name, json_body[:display_name]
      end

      test "wrong credentials are a 401 envelope" do
        post_json "/api/v1/session", params: { email_address: @user.email_address, password: "nope" }

        assert_response :unauthorized
        assert_equal "unauthorized", json_body.dig(:error, :code)
      end

      test "a banned account cannot sign in" do
        post_json "/api/v1/session", params: { email_address: users(:banned).email_address, password: "password" }

        assert_response :forbidden
        assert_equal "banned", json_body.dig(:error, :code)
      end

      test "a missing token is a 401 envelope with a message" do
        get_json "/api/v1/me"

        assert_response :unauthorized
        error = json_body[:error]
        assert_equal "unauthorized", error[:code]
        assert_not error[:message].blank?
      end

      test "sign-out revokes the token in use" do
        raw = ApiToken.issue_for(@user, name: "test")
        use_token @user, raw
        delete_json "/api/v1/session"

        assert_response :ok
        assert_equal 0, @user.api_tokens.reload.count

        get_json "/api/v1/me"
        assert_response :unauthorized
      end

      test "the token list shows metadata and revoking one takes effect" do
        raw = ApiToken.issue_for(@user, name: "Phone")
        get_json "/api/v1/api_tokens", auth_as: @user

        assert_response :ok
        listed = json_body[:api_tokens].find { |t| t[:name] == "Phone" }
        assert_not listed.nil?
        assert_nil listed[:token], "the plaintext must never be listed"

        delete_json "/api/v1/api_tokens/#{listed[:id]}", auth_as: @user
        assert_response :ok

        use_token @user, raw
        get_json "/api/v1/api_tokens"
        assert_response :unauthorized
      end

      test "addresses validate through the model" do
        post_json "/api/v1/addresses", auth_as: @user, params: {
          full_name: "Mauro Test", line1: "Calle Mayor 1", city: "Madrid",
          postal_code: "28001", country_code: "ES"
        }
        assert_response :created
        address = json_body[:address]
        assert_equal "Madrid", address[:city]

        post_json "/api/v1/addresses", auth_as: @user, params: { full_name: "", line1: "" }
        assert_response :unprocessable_entity
        assert_equal "invalid_request", json_body.dig(:error, :code)
        assert_not json_body.dig(:error, :details).blank?

        delete_json "/api/v1/addresses/#{address[:id]}", auth_as: @user
        assert_response :no_content
      end
    end
  end
end
