require "test_helper"

module Api
  module V1
    # Order transitions keep the web app's role split: buyer-only routes look
    # the order up through current_user.orders, seller-only routes through
    # current_user.sales, so the wrong role 404s instead of 403.
    class OrdersTransitionTest < ActionDispatch::IntegrationTest
      setup do
        @order = orders(:one) # buyer: one, seller: two, status: completed
        @buyer = users(:one)
        @seller = users(:two)
      end

      test "a seller cannot use a buyer transition" do
        post_json "/api/v1/orders/#{@order.id}/completion", {}, auth_as: @seller

        assert_response :not_found
        assert_equal "not_found", json_body.dig(:error, :code)
      end

      test "a buyer cannot confirm payment or shipment" do
        %w[payment_confirmation shipment].each do |segment|
          post_json "/api/v1/orders/#{@order.id}/#{segment}", { carrier: "Correos" }, auth_as: @buyer
          assert_response :not_found, "#{segment} was reachable by the buyer"
        end
      end

      test "a buyer cannot confirm a shipment" do
        post_json "/api/v1/orders/#{@order.id}/shipment", { carrier: "Correos" }, auth_as: @buyer

        assert_response :not_found
      end

      test "an outsider cannot touch any transition" do
        outsider = users(:admin)

        %w[shipment cancellation completion dispute delivery_confirmation payment_confirmation].each do |segment|
          post_json "/api/v1/orders/#{@order.id}/#{segment}", {}, auth_as: outsider
          assert_response :not_found, "#{segment} leaked another person's order"
        end
      end

      test "a completed order cannot be cancelled" do
        post_json "/api/v1/orders/#{@order.id}/cancellation", {}, auth_as: @buyer

        assert_response :conflict
        assert_equal "stale_transition", json_body.dig(:error, :code)
        assert_not json_body.dig(:error, :message).blank?
      end

      test "an unknown carrier is refused before the transition runs" do
        order = orders(:two) # seller: one, so this seller may ship it
        post_json "/api/v1/orders/#{order.id}/shipment", { carrier: "Teleporter" }, auth_as: @buyer

        assert_response :unprocessable_entity
        assert_equal "unknown_carrier", json_body.dig(:error, :code)
      end
    end
  end
end
