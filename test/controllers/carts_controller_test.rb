require "test_helper"

class CartsControllerTest < ActionDispatch::IntegrationTest
  # --- guest cart (signed cookie) -----------------------------------------

  test "a guest gets a cart keyed by a signed cookie" do
    get cart_path
    assert_response :success
    assert cookies[:cart_token].present?

    cart = Cart.where(user: nil).order(:id).last
    assert_not_nil cart
    assert cart.token.present?
  end

  test "the guest cart persists across requests and merges into the user cart on login" do
    listings(:as_new).update!(quantity: 5)
    post cart_items_path, params: { listing_id: listings(:as_new).to_param, quantity: 2 }
    assert_redirected_to cart_path
    guest_cart = Cart.where(user: nil).order(:id).last
    assert_equal 2, guest_cart.cart_items.sum(:quantity)

    post session_path, params: { email_address: "admin@example.com", password: "password" }
    assert_redirected_to root_path
    assert cookies[:cart_token].blank?

    admin_cart = Cart.for_user(users(:admin))
    assert_equal 1, admin_cart.cart_items.count
    assert_equal listings(:as_new).id, admin_cart.cart_items.first.listing_id
    assert_not Cart.exists?(guest_cart.id)
  end

  # --- add / update / remove ----------------------------------------------

  test "adding a purchasable listing lands in the current cart" do
    sign_in_as users(:one)
    assert_difference -> { CartItem.count }, 1 do
      post cart_items_path, params: { listing_id: listings(:as_new).to_param, quantity: 1 }
    end
    assert_equal 1, current_cart_item_count
  end

  test "adding your own listing is refused" do
    sign_in_as users(:one)
    assert_no_difference -> { CartItem.count } do
      post cart_items_path, params: { listing_id: listings(:gigabyte).to_param }
    end
    assert_redirected_to cart_path
    assert_not flash[:alert].blank?
  end

  test "other people's cart items 404" do
    item = Cart.for_user(users(:one)).tap { |c| c.cart_items.create!(listing: listings(:as_new), quantity: 1) }.cart_items.first

    sign_in_as users(:two)
    patch cart_item_path(item), params: { cart_item: { quantity: 3 } }
    assert_response :not_found
    assert_equal 1, item.reload.quantity
  end

  test "quantity updates respect stock" do
    sign_in_as users(:one)
    listings(:as_new).update!(quantity: 5)
    item = Cart.for_user(users(:one)).cart_items.create!(listing: listings(:as_new), quantity: 1)

    patch cart_item_path(item), params: { cart_item: { quantity: 4 } }
    assert_redirected_to cart_path
    assert_equal 4, item.reload.quantity

    patch cart_item_path(item), params: { cart_item: { quantity: 6 } }
    assert_redirected_to cart_path
    assert_equal 4, item.reload.quantity

    patch cart_item_path(item), params: { cart_item: { quantity: "0" } }
    assert_equal 4, item.reload.quantity
  end

  test "removing an item empties it from the cart" do
    sign_in_as users(:one)
    item = Cart.for_user(users(:one)).cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_difference -> { CartItem.count }, -1 do
      delete cart_item_path(item)
    end
  end

  # --- wishlist intent ------------------------------------------------------

  test "save-to-wishlist needs an account: guests are sent to sign in with a return path" do
    post cart_items_path, params: { listing_id: listings(:as_new).to_param, quantity: 1 }
    item = Cart.where(user: nil).order(:id).last.cart_items.first

    patch cart_item_path(item), params: { intent: "wishlist" }
    assert_redirected_to new_session_path
    assert_predicate item.reload, :persisted?
    assert_equal cart_path, session[:return_to_after_authenticating]
  end

  test "save-to-wishlist moves the item into favorites for signed-in users" do
    sign_in_as users(:two)
    item = Cart.for_user(users(:two)).cart_items.create!(listing: listings(:gigabyte), quantity: 1)

    assert_difference -> { Favorite.count }, 1 do
      assert_difference -> { CartItem.count }, -1 do
        patch cart_item_path(item), params: { intent: "wishlist" }
      end
    end
    assert_redirected_to cart_path
    assert Favorite.exists?(user: users(:two), listing: listings(:gigabyte))
  end

  private

  def current_cart_item_count
    Cart.for_user(users(:one)).cart_items.count
  end
end
