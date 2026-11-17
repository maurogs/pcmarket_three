require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_secret"
    @order = create_pending_order
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  def create_pending_order
    order = Order.create!(buyer: users(:one), seller: users(:two),
                          subtotal_cents: 33_000, currency: "EUR",
                          payment_reference: "cs_test_1")
    order.order_items.create!(listing: listings(:as_new), title: "x", price_cents: 33_000, quantity: 1)
    order
  end

  def session_payload(session_id: "cs_test_1", order_ids: nil, type: "checkout.session.completed")
    order_ids ||= @order.id
    {
      id: "evt_test_1", object: "event",
      type: type,
      data: { object: { id: session_id, object: "checkout.session",
                        metadata: { order_ids: order_ids.to_s } } }
    }.to_json
  end

  def signed_headers(payload, secret: ENV.fetch("STRIPE_WEBHOOK_SECRET"), timestamp: Time.now.to_i, signature: nil)
    body = signature || OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    { "CONTENT_TYPE" => "application/json",
      "HTTP_STRIPE_SIGNATURE" => "t=#{timestamp},v1=#{body}" }
  end

  def post_event(payload, headers)
    post stripe_webhooks_path, params: payload, headers: headers
  end

  test "a correctly signed checkout.session.completed marks the order paid" do
    payload = session_payload
    assert_difference -> { Notification.count }, 1 do
      post_event(payload, signed_headers(payload))
    end
    assert_response :ok

    @order.reload
    assert_predicate @order, :paid?
    assert_not_nil @order.paid_at
    assert_equal "order_paid", Notification.order(:id).last.kind
    assert_equal users(:two), Notification.order(:id).last.user
  end

  test "a correctly signed checkout.session.expired cancels the order" do
    payload = session_payload(type: "checkout.session.expired")

    post_event(payload, signed_headers(payload))
    assert_response :ok

    @order.reload
    assert_predicate @order, :cancelled?
    assert_not_nil @order.cancelled_at
  end

  test "an event with a bad signature is rejected and never applied" do
    payload = session_payload
    post_event(payload, signed_headers(payload, secret: "whsec_wrong"))
    assert_response :bad_request
    assert_predicate @order.reload, :pending_payment?
  end

  test "an event signed with the right key but tampered payload is rejected" do
    payload = session_payload
    headers = signed_headers(session_payload(order_ids: 999_999))
    post_event(payload, headers)
    assert_response :bad_request
    assert_predicate @order.reload, :pending_payment?
  end

  test "an event with an old timestamp is rejected" do
    payload = session_payload
    post_event(payload, signed_headers(payload, timestamp: 5_000))
    assert_response :bad_request
    assert_predicate @order.reload, :pending_payment?
  end

  test "a request with no signature header is rejected" do
    post stripe_webhooks_path, params: session_payload,
                               headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
    assert_predicate @order.reload, :pending_payment?
  end
end
