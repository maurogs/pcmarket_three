require "test_helper"

module Offers
  class DecisionsTest < ActiveSupport::TestCase
    setup do
      @listing = listings(:gigabyte)
      @offer = Offer.create!(listing: @listing, buyer: users(:two),
                             amount_cents: 40_000, expires_at: Time.current + Offer::OFFER_TTL)
      @other = Offer.create!(listing: @listing, buyer: users(:admin),
                             amount_cents: 45_000, expires_at: Time.current + Offer::OFFER_TTL)
    end

    test "accepting reserves the listing for the buyer" do
      result = Offers::Accept.call(offer: @offer)

      assert_nil result.error
      assert_predicate @offer.reload, :accepted?
      @listing.reload
      assert_predicate @listing, :reserved?
      assert_equal users(:two), @listing.reserved_for
      assert_in_delta (Time.current + Listing::RESERVATION_TTL).to_i, @listing.reserved_until.to_i, 5
    end

    test "accepting auto-declines the other pending offers and notifies the buyer" do
      Offers::Accept.call(offer: @offer)

      assert_predicate @other.reload, :declined?
      assert Notification.exists?(user: users(:two), kind: "offer_accepted")
    end

    test "accepting a time-expired (but not yet swept) offer comes back stale" do
      @offer.update!(expires_at: Time.current - 1.minute)

      assert_equal :stale, Offers::Accept.call(offer: @offer).error
      assert_predicate @offer.reload, :pending?
      assert_predicate @listing.reload, :approved?
    end

    test "accepting a non-pending offer comes back stale" do
      @offer.decline!

      assert_equal :stale, Offers::Accept.call(offer: @offer).error
    end

    test "the second accept on the same listing comes back stale (row locks re-check state)" do
      assert_nil Offers::Accept.call(offer: @offer).error

      # @other was auto-declined by the first accept; under the listing +
      # offer row locks its state is re-read before transitioning, so the
      # second accept is refused instead of double-reserving.
      result = Offers::Accept.call(offer: @other)
      assert_equal :stale, result.error
      assert_predicate @other.reload, :declined?
      @listing.reload
      assert_predicate @listing, :reserved?
      assert_equal users(:two), @listing.reserved_for
    end

    test "decline only works on pending offers" do
      assert_nil Offers::Decline.call(offer: @other).error
      assert_predicate @other.reload, :declined?
      assert_equal :stale, Offers::Decline.call(offer: @other).error
    end

    test "withdraw only works on pending offers" do
      assert_nil Offers::Withdraw.call(offer: @offer).error
      assert_predicate @offer.reload, :withdrawn?
      assert_equal :stale, Offers::Withdraw.call(offer: @offer).error
    end
  end
end
