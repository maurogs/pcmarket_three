require "test_helper"

# Dispute resolution service (Phase 6b): the two admin outcomes on a disputed
# order — refund the buyer (Stripe-backed when there is a payment_reference)
# or release the money to the seller. Audit rows are written by the
# controller, not here, so this file asserts state, money and notifications.
class DisputesResolveTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @buyer = users(:one)
    @seller = users(:two)
  end

  # Minitest 6 ships no Object#stub: intercept StripeRefund.new on the class
  # singleton and stub the instance's network `call`, so the real class-level
  # wiring (and its amount defaulting) still runs but no HTTP happens.
  def with_fake_stripe_refund
    calls = []
    original_new = Payments::StripeRefund.singleton_class.instance_method(:new)

    Payments::StripeRefund.singleton_class.define_method(:new) do |*args, **kwargs|
      instance = super(*args, **kwargs)
      instance.singleton_class.define_method(:call) do
        calls << { order: order, amount_cents: amount_cents }
        nil
      end
      instance
    end

    yield calls
  ensure
    Payments::StripeRefund.singleton_class.define_method(:new, original_new)
  end

  test "full refund charges Stripe for the whole total and marks the order refunded" do
    order = disputed_order(number: "PCM-2024-900111", payment_reference: "cs_test_111")

    calls = nil
    assert_difference "Notification.count", 2 do
      with_fake_stripe_refund do |captured|
        assert_enqueued_emails 2 do
          result = Disputes::Resolve.call(order: order, action: "refund")
          assert_nil result.error
          assert_equal order, result.order
        end
        calls = captured
      end
    end

    assert_equal 1, calls.size
    # Resolve passes nil for a full refund; Payments::StripeRefund then falls
    # back to order.total_cents.
    assert_nil calls.first[:amount_cents]
    assert_equal "cs_test_111", calls.first[:order].payment_reference
    assert_equal order.total_cents, calls.first[:amount_cents] || calls.first[:order].total_cents

    order.reload
    assert_predicate order, :refunded?
    assert_equal 50_000, order.refund_cents

    kinds = Notification.where(user: [ @buyer, @seller ]).pluck(:user_id, :kind).to_h
    assert_equal "order_refunded", kinds[@buyer.id]
    assert_equal "order_refunded", kinds[@seller.id]
  end

  test "partial refund keeps the requested amount below the total" do
    order = disputed_order(number: "PCM-2024-900112", payment_reference: "cs_test_112")

    calls = nil
    with_fake_stripe_refund do |captured|
      result = Disputes::Resolve.call(order: order, action: "refund", amount_cents: 20_000)
      assert_nil result.error
      calls = captured
    end

    assert_equal 1, calls.size
    assert_equal 20_000, calls.first[:amount_cents]

    order.reload
    assert_predicate order, :refunded?
    assert_equal 20_000, order.refund_cents
  end

  test "a refund above the total is refused without touching Stripe" do
    order = disputed_order(number: "PCM-2024-900113", payment_reference: "cs_test_113")

    calls = nil
    assert_no_difference [ "Notification.count", "OrderNote.count" ] do
      with_fake_stripe_refund do |captured|
        result = Disputes::Resolve.call(order: order, action: "refund", amount_cents: 60_000)
        assert_equal :amount_above_total, result.error
        assert_nil result.order
        calls = captured
      end
    end

    assert_empty calls
    order.reload
    assert_predicate order, :disputed?
    assert_equal 0, order.refund_cents
  end

  test "zero and negative refund amounts are refused" do
    { "PCM-2024-900114" => 0, "PCM-2024-900115" => -100 }.each do |number, amount|
      order = disputed_order(number: number)

      with_fake_stripe_refund do |captured|
        result = Disputes::Resolve.call(order: order, action: "refund", amount_cents: amount)
        assert_equal :amount_above_total, result.error
        assert_empty captured
      end
      assert_predicate order.reload, :disputed?
    end
  end

  test "a refund amount that is not a number is refused" do
    order = disputed_order(number: "PCM-2024-900116")

    result = Disputes::Resolve.call(order: order, action: "refund", amount_cents: "fifty euros")
    assert_equal :invalid_amount, result.error
    assert_predicate order.reload, :disputed?
  end

  test "direct bank payments are refunded without calling the gateway" do
    order = disputed_order(number: "PCM-2024-900117") # no payment_reference

    calls = nil
    with_fake_stripe_refund do |captured|
      result = Disputes::Resolve.call(order: order, action: "refund")
      assert_nil result.error
      calls = captured
    end

    assert_empty calls
    order.reload
    assert_predicate order, :refunded?
    assert_equal 50_000, order.refund_cents
  end

  test "release completes the order in the seller's favour" do
    order = disputed_order(number: "PCM-2024-900118")

    assert_difference "Notification.count", 2 do
      assert_enqueued_emails 2 do
        result = Disputes::Resolve.call(order: order, action: "release")
        assert_nil result.error
      end
    end

    order.reload
    assert_predicate order, :completed?
    assert_not_nil order.completed_at
    assert_equal 0, order.refund_cents

    kinds = Notification.where(user: [ @buyer, @seller ]).pluck(:user_id, :kind).to_h
    assert_equal "order_resolved", kinds[@buyer.id]
    assert_equal "order_resolved", kinds[@seller.id]
  end

  test "release keeps an existing completed_at stamp" do
    order = disputed_order(number: "PCM-2024-900119")
    stamp = 5.days.ago
    order.update_columns(completed_at: stamp)

    Disputes::Resolve.call(order: order, action: "release")
    assert_equal stamp.to_i, order.reload.completed_at.to_i
  end

  test "only disputed orders can be resolved" do
    completed = orders(:one)

    result = Disputes::Resolve.call(order: completed, action: "refund")
    assert_equal :not_disputed, result.error
    assert_predicate completed.reload, :completed?
  end

  test "an unknown action is refused" do
    order = disputed_order(number: "PCM-2024-900120")

    result = Disputes::Resolve.call(order: order, action: "split_the_difference")
    assert_equal :invalid_action, result.error
    assert_predicate order.reload, :disputed?
  end

  private

  def disputed_order(number:, payment_reference: nil)
    Order.create!(number: number, buyer: @buyer, seller: @seller, status: :disputed,
                  subtotal_cents: 50_000, payment_provider: payment_reference && "stripe",
                  payment_reference: payment_reference, paid_at: 3.days.ago,
                  shipped_at: 2.days.ago, delivered_at: 1.day.ago,
                  buyer_protection_until: 1.day.from_now)
  end
end
