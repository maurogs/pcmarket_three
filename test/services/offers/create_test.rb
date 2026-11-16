require "test_helper"

module Offers
  class CreateTest < ActiveSupport::TestCase
    setup do
      @listing = listings(:gigabyte) # 599,99 €, offers allowed by default
    end

    test "places a valid offer with a 48h deadline and notifies the seller" do
      result = Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000)

      assert_nil result.error
      offer = result.offer
      assert_predicate offer, :pending?
      assert_equal 40_000, offer.amount_cents
      assert_in_delta (Time.current + 48.hours).to_i, offer.expires_at.to_i, 5
      assert Notification.exists?(user: users(:one), kind: "new_offer")
    end

    test "posts an offer card into the thread (creating it if needed)" do
      result = Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000)

      message = Message.where(offer: result.offer).sole
      assert_equal "offer", message.kind
      assert_equal users(:two), message.sender
      assert_includes message.body, "400.00" # chat card body mentions the amount
    end

    test "a new offer withdraws the buyer's previous pending offer" do
      Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000)
      second = Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 45_000).offer

      assert_equal 1, Offer.active.where(buyer: users(:two), listing: @listing).count
      assert_equal second, Offer.active.sole
      assert_equal 1, Offer.withdrawn.where(buyer: users(:two)).count
    end

    test "buyers cannot offer on their own listing" do
      assert_equal :self, Offers::Create.call(listing: @listing, buyer: users(:one), amount_cents: 1).error
    end

    test "unapproved listings and offer-less stores refuse offers" do
      assert_equal :not_allowed,
                   Offers::Create.call(listing: listings(:pending), buyer: users(:two), amount_cents: 10_000).error

      @listing.store.update!(allow_offers_default: false)
      assert_equal :not_allowed,
                   Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000).error
    end

    test "vacation-mode sellers do not take offers" do
      @listing.store.enable_vacation!

      assert_equal :vacation, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000).error
    end

    test "amount must be a positive integer" do
      assert_equal :invalid, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: nil).error
      assert_equal :invalid, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: "40").error
      assert_equal :invalid, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 0).error
    end

    test "minimum is min_offer_percent of the price; below it reports the floor" do
      result = Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 29_999)

      assert_equal :below_minimum, result.error
      assert_equal 30_000, result.min_amount_cents # ceil(59999 * 0.5)

      Setting.set("min_offer_percent", 80)
      result = Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 40_000)
      assert_equal :below_minimum, result.error
      assert_equal 48_000, result.min_amount_cents
    ensure
      Setting.set("min_offer_percent", 50)
    end

    test "offers at or above the asking price are refused" do
      assert_equal :above_price, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 59_999).error
      assert_equal :above_price, Offers::Create.call(listing: @listing, buyer: users(:two), amount_cents: 70_000).error
    end
  end
end
