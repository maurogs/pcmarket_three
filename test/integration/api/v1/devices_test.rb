require "test_helper"

module Api
  module V1
    # Push-device endpoints for the mobile clients: registration upserts by
    # push token, the echo masks the token, and unregistration is final.
    class DevicesTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
      end

      test "devices register idempotently and never echo the push token" do
        long_token = "push-token-#{'x' * 30}"
        post_json "/api/v1/devices", auth_as: @user,
                                     params: { push_token: long_token, platform: "ios" }
        assert_response :created
        device = json_body[:device]
        assert_equal "#{long_token[0, 24]}…", device[:push_token]

        post_json "/api/v1/devices", auth_as: @user,
                                     params: { push_token: long_token, platform: "android" }
        assert_response :created
        assert_equal 1, @user.devices.count

        get_json "/api/v1/devices", auth_as: @user
        assert_equal 1, json_body[:devices].size
      end

      test "unregistering a device deletes it" do
        post_json "/api/v1/devices", auth_as: @user,
                                     params: { push_token: "push-token-#{'y' * 30}", platform: "ios" }
        assert_response :created
        device_id = json_body.dig(:device, :id)

        delete_json "/api/v1/devices/#{device_id}", auth_as: @user
        assert_response :ok
        assert_equal 0, @user.devices.reload.count
      end
    end
  end
end
