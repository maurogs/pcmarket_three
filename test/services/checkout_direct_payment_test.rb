require "test_helper"

class CheckoutDirectPaymentTest < ActiveSupport::TestCase
  setup do
    @buyer = users(:admin)
    @cart = Cart.for_user(@buyer)
    @address = addresses(:one)
  end

  def place(token = SecureRandom.base58(24))
    Checkout::PlaceOrders.call(buyer: @buyer, cart: @cart, address: @address,
                               checkout_token: token)
  end

  test "posts a system message with the order number into the seeded thread" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    orders = place.orders
    conversation = Conversation.create!(listing: listings(:as_new), buyer: @buyer, seller: users(:two))

    result = Checkout::DirectPayment.call(orders: orders, buyer: @buyer)
    assert_equal conversation.id, result.conversation.id
    assert_not_predicate result, :multiple

    message = conversation.messages.order(:id).last
    assert_predicate message, :system?
    assert_equal @buyer, message.sender
    assert_includes message.body, orders.first.number
  end

  test "the thread is created when it does not exist yet" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    orders = place.orders

    assert_difference -> { Conversation.count }, 1 do
      Checkout::DirectPayment.call(orders: orders, buyer: @buyer)
    end
    assert Conversation.exists?(listing: listings(:as_new), buyer: @buyer, seller: users(:two))
  end

  test "several sellers flag multiple and return the first thread" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)    # seller two
    @cart.cart_items.create!(listing: listings(:featured), quantity: 1)  # seller one

    result = Checkout::DirectPayment.call(orders: place.orders, buyer: @buyer)
    assert_predicate result, :multiple
    assert_not_nil result.conversation
    assert_equal 2, Conversation.where(buyer: @buyer).count
    assert_equal 2, Message.where(kind: :system).count
  end
end
