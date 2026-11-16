require "test_helper"

class OfferTest < ActiveSupport::TestCase
  setup do
    @listing = listings(:gigabyte)
    @offer = Offer.create!(listing: @listing, buyer: users(:two),
                           amount_cents: 40_000, expires_at: Time.current + Offer::OFFER_TTL)
  end

  test "amount must be a positive integer" do
    assert_not Offer.new(listing: @listing, buyer: users(:two), amount_cents: 0).valid?
    assert_not Offer.new(listing: @listing, buyer: users(:two), amount_cents: -5).valid?
  end

  test "expires_at defaults are set by the service, time_expired? is time based" do
    assert_not @offer.time_expired?
    @offer.update!(expires_at: Time.current - 1.minute)
    assert @offer.time_expired?
    assert_not @offer.actionable?
  end

  test "accept! reserves; declining/withdrawing/expiring only work while pending" do
    @offer.accept!
    assert_predicate @offer, :accepted?
    assert_raises(Offer::InvalidTransition) { @offer.decline! }
    assert_raises(Offer::InvalidTransition) { @offer.withdraw! }
  end

  test "accept! is refused after the deadline even before the job runs" do
    @offer.update!(expires_at: Time.current - 1.second)
    assert_raises(Offer::InvalidTransition) { @offer.accept! }
    assert_predicate @offer.reload, :pending?
  end

  test "expire! flips a pending offer" do
    @offer.expire!
    assert_predicate @offer, :expired?
  end

  test "for_seller and sent_by scopes power the received/sent tabs" do
    assert_includes Offer.for_seller(users(:one)), @offer
    assert_not_includes Offer.for_seller(users(:two)), @offer
    assert_includes Offer.sent_by(users(:two)), @offer
    assert_not_includes Offer.sent_by(users(:one)), @offer
  end

  test "conversation finds the thread the offer card lives in" do
    conversation = Conversation.create!(
      listing: @listing, buyer: users(:two), seller: users(:one)
    )
    assert_equal conversation, @offer.conversation
  end
end
