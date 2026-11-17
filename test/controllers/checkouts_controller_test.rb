require "test_helper"

class CheckoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.disable(:stripe_checkout)
    ENV.delete("STRIPE_SECRET_KEY")
  end

  def setup_cart
    sign_in_as users(:one)
    Cart.for_user(users(:one)).cart_items.create!(listing: listings(:as_new), quantity: 1)
  end

  test "guests are sent to sign in" do
    get checkout_path
    assert_redirected_to new_session_path
  end

  test "an empty cart cannot reach checkout" do
    sign_in_as users(:one)
    get checkout_path
    assert_redirected_to cart_path
    get checkout_path # ensure_cart runs before the token mint: still bounced
    assert_redirected_to cart_path
  end

  test "the checkout page mints a one-time token kept in the session" do
    setup_cart
    get checkout_path
    assert_response :success
    assert_not_nil session[:checkout_token]
    token = session[:checkout_token]

    get checkout_path
    assert_not_equal token, session[:checkout_token] # fresh token every render
  end

  test "a stale form token is refused" do
    setup_cart
    get checkout_path
    assert_no_difference -> { Order.count } do
      post checkout_path, params: { checkout_token: "nope", address_id: addresses(:one).id }
    end
    assert_redirected_to checkout_path
  end

  test "no address is refused" do
    setup_cart
    get checkout_path
    assert_no_difference -> { Order.count } do
      post checkout_path, params: { checkout_token: session[:checkout_token] }
    end
    assert_redirected_to checkout_path
  end

  test "direct mode places the orders, seeds the thread and redirects to the conversation" do
    setup_cart
    get checkout_path
    token = session[:checkout_token]

    assert_difference -> { Order.count }, 1 do
      post checkout_path, params: { checkout_token: token, address_id: addresses(:one).id }
    end

    order = Order.last
    assert_equal users(:one), order.buyer
    assert_equal users(:two), order.seller
    assert_equal "direct", order.payment_provider
    assert_predicate Cart.for_user(users(:one)).cart_items.reload, :empty?

    conversation = Conversation.find_by(listing: listings(:as_new), buyer: users(:one), seller: users(:two))
    assert_not_nil conversation
    assert_equal order.number, conversation.messages.last.body[/PCM-\d{4}-\d{6}/]
    assert_redirected_to conversation_path(conversation)
  end

  test "replaying the same token does not place a second purchase" do
    setup_cart
    get checkout_path
    token = session[:checkout_token]
    before = Order.count
    post checkout_path, params: { checkout_token: token, address_id: addresses(:one).id }
    assert_equal before + 1, Order.count

    post checkout_path, params: { checkout_token: token, address_id: addresses(:one).id }
    assert_equal before + 1, Order.count
    assert_redirected_to orders_path
  end

  test "pickup is passed through per seller" do
    listings(:as_new).update!(local_pickup: true, shipping_price_cents: 499)
    setup_cart
    get checkout_path

    post checkout_path, params: { checkout_token: session[:checkout_token],
                                  address_id: addresses(:one).id,
                                  pickup: { users(:two).id.to_s => "1" } }
    assert_equal 0, Order.last.shipping_cents
  end

  test "stripe mode redirects to the checkout session when the flag and key are on" do
    setup_cart
    Flipper.enable(:stripe_checkout)
    ENV["STRIPE_SECRET_KEY"] = "sk_test_fake"
    stripe_session = Struct.new(:id, :url).new("cs_test_redir", "https://checkout.stripe.com/pay/cs_test_redir")

    Stripe::Checkout::Session.singleton_class.define_method(:create) { |_params| stripe_session }
    begin
      get checkout_path
      post checkout_path, params: { checkout_token: session[:checkout_token],
                                    address_id: addresses(:one).id }
    ensure
      Stripe::Checkout::Session.singleton_class.remove_method(:create)
    end

    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_redir"
    assert_equal "stripe", Order.last.payment_provider
    assert_equal "cs_test_redir", Order.last.payment_reference
  ensure
    Flipper.disable(:stripe_checkout)
    ENV.delete("STRIPE_SECRET_KEY")
  end

  test "a sold-out cart item makes checkout fail with an error, not an order" do
    setup_cart
    listings(:as_new).update!(status: :sold)
    get checkout_path

    assert_no_difference -> { Order.count } do
      post checkout_path, params: { checkout_token: session[:checkout_token], address_id: addresses(:one).id }
    end
    assert_redirected_to checkout_path
  end
end
