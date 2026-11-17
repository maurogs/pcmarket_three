require "test_helper"

module Listings
  class PriceDropNotifierTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    setup do
      @listing = listings(:gigabyte)
      @original_price = @listing.price_cents
      @favorite = Favorite.create!(user: users(:two), listing: @listing,
                                   price_cents_at_save: @original_price)
    end

    test "notifies the saver and enqueues the e-mail on a price cut" do
      @listing.update!(price_cents: @original_price - 5_000)

      notification = Notification.find_by(user: users(:two), kind: "price_drop")
      assert notification
      assert_equal @listing.id, notification.payload["listing_id"]
      assert_enqueued_emails 1
    end

    test "a second cut inside the cooldown window does not alert again" do
      @listing.update!(price_cents: @original_price - 5_000)
      @listing.update!(price_cents: @original_price - 10_000)

      assert_equal 1, Notification.where(kind: "price_drop", user: users(:two)).count
      assert_enqueued_emails 1
    end

    test "no alert when the price did not go below the saved price" do
      @favorite.update!(price_cents_at_save: @original_price - 50_000)
      @listing.update!(price_cents: @original_price - 5_000)

      assert_equal 0, Notification.where(kind: "price_drop").count
      assert_enqueued_emails 0
    end

    test "users who opted out of price-drop e-mail get the notification but no e-mail" do
      @favorite.user.update!(notification_preferences: { "email_price_drop" => false })
      @listing.update!(price_cents: @original_price - 5_000)

      assert_equal 1, Notification.where(kind: "price_drop", user: users(:two)).count
      assert_enqueued_emails 0
    end
  end
end
