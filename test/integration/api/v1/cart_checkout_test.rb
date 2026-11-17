require "test_helper"

module Api
  module V1
    # Cart, checkout and the order inbox. Purchase rules are Carts::AddItem's
    # and Checkout::PlaceOrders'; these tests only pin the HTTP contract.
    class CartCheckoutTest < ActionDispatch::IntegrationTest
      setup do
        @buyer = users(:one)
        @listing = listings(:as_new) # owned by users(:two), approved, in stock
      end

      test "the cart starts empty and is public to its owner only" do
        get_json "/api/v1/cart", auth_as: @buyer

        assert_response :ok
        assert_equal 0, json_body.dig(:cart, :items_count)
        assert_not json_body.dig(:cart, :checkout_available)
      end

      test "adding a line, capping it at stock and clearing it" do
        post_json "/api/v1/cart_items", { listing_id: @listing.id, quantity: 1 }, auth_as: @buyer
        assert_response :created
        item = json_body[:cart_item]
        assert_equal @listing.slug, item.dig(:listing, :slug)
        assert_equal 1, item[:quantity]

        get_json "/api/v1/cart", auth_as: @buyer
        assert_equal 1, json_body.dig(:cart, :items_count)
        assert json_body.dig(:cart, :checkout_available)

        patch_json "/api/v1/cart_items/#{item[:id]}", { quantity: @listing.quantity + 3 }, auth_as: @buyer
        assert_response :unprocessable_entity
        assert_equal "quantity_exceeded", json_body.dig(:error, :code)

        # quantity 0 is the web cart's "−": it removes the line.
        patch_json "/api/v1/cart_items/#{item[:id]}", { quantity: 0 }, auth_as: @buyer
        assert_response :ok
        assert_nil json_body[:cart_item]
        assert_equal 0, Cart.for_user(@buyer).cart_items.count
      end

      test "quantity beyond stock is refused with the shared envelope" do
        post_json "/api/v1/cart_items", { listing_id: @listing.id, quantity: @listing.quantity + 5 },
                  auth_as: @buyer

        assert_response :unprocessable_entity
        assert_equal "quantity_exceeded", json_body.dig(:error, :code)
        assert_not json_body.dig(:error, :message).blank?
      end

      test "a seller cannot buy their own listing" do
        post_json "/api/v1/cart_items", { listing_id: listings(:gigabyte).id }, auth_as: users(:one)

        assert_response :unprocessable_entity
        assert_equal "own_listing", json_body.dig(:error, :code)
      end

      test "cart items of another user are not addressable" do
        post_json "/api/v1/cart_items", { listing_id: @listing.id }, auth_as: @buyer
        id = json_body.dig(:cart_item, :id)

        patch_json "/api/v1/cart_items/#{id}", { quantity: 1 }, auth_as: users(:admin)
        assert_response :not_found
      end

      test "checkout with someone else's address is refused" do
        post_json "/api/v1/checkout", { address_id: addresses(:two).id }, auth_as: @buyer

        assert_response :unprocessable_entity
        assert_equal "invalid_address", json_body.dig(:error, :code)
      end

      test "checkout of an empty cart fails with the shared envelope" do
        post_json "/api/v1/checkout", { address_id: addresses(:one).id }, auth_as: @buyer

        assert_response :unprocessable_entity
        assert_equal "empty_cart", json_body.dig(:error, :code)
        assert_not json_body.dig(:error, :message).blank?
      end

      test "checkout in direct mode places the cart and is replay-safe" do
        post_json "/api/v1/cart_items", { listing_id: @listing.id, quantity: 1 }, auth_as: @buyer
        assert_response :created
        token = SecureRandom.base58(24)

        order_ids = nil
        assert_difference -> { Order.count }, 1 do
          post_json "/api/v1/checkout", { address_id: addresses(:one).id, checkout_token: token },
                    auth_as: @buyer
          assert_response :created
          body = json_body
          assert_equal "direct", body[:mode]
          assert_equal token, body[:checkout_token]
          assert_equal 1, body[:order_ids].size
          assert_equal 1, body[:conversation_ids].size
          assert_nil body[:redirect_url]
          order_ids = body[:order_ids]
        end

        # The cart is emptied by a successful checkout.
        get_json "/api/v1/cart", auth_as: @buyer
        assert_equal 0, json_body.dig(:cart, :items_count)

        # The same token replays: no second order, same ids.
        assert_no_difference -> { Order.count } do
          post_json "/api/v1/checkout", { address_id: addresses(:one).id, checkout_token: token },
                    auth_as: @buyer
          assert_response :created
          assert_equal order_ids, json_body[:order_ids]
        end
      end

      test "orders come back per role and strangers get a 404" do
        order = orders(:one) # buyer: one, seller: two
        get_json "/api/v1/orders", auth_as: @buyer
        assert_response :ok
        assert_includes json_body[:orders].map { |o| o[:number] }, order.number
        assert_not json_body[:meta][:pagination][:total_pages].nil?

        get_json "/api/v1/orders?role=seller", auth_as: @buyer
        assert_equal orders(:two).number, json_body[:orders].first[:number]

        get_json "/api/v1/orders/#{order.id}", auth_as: users(:admin)
        assert_response :not_found

        get_json "/api/v1/orders/#{order.id}", auth_as: @buyer
        assert_response :ok
        assert_equal order.number, json_body.dig(:order, :number)
        assert_equal 1, json_body.dig(:order, :items).size
        assert_not json_body.dig(:order, :total_money).nil?
      end
    end
  end
end
