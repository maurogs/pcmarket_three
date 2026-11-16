require "test_helper"

class ExpireOffersJobTest < ActiveSupport::TestCase
  setup do
    @listing = listings(:gigabyte)
    @reserved = listings(:as_new)

    @due = Offer.create!(listing: @listing, buyer: users(:two),
                         amount_cents: 40_000, expires_at: Time.current - 1.hour)
    @fresh = Offer.create!(listing: @listing, buyer: users(:admin),
                           amount_cents: 41_000, expires_at: Time.current + 1.hour)

    @reserved.update!(status: :reserved, reserved_for: users(:one),
                      reserved_until: Time.current - 1.minute)
  end

  test "time-expired pending offers flip to expired, fresh ones stay" do
    ExpireOffersJob.perform_now

    assert_predicate @due.reload, :expired?
    assert_predicate @fresh.reload, :pending?
  end

  test "lapsed reservations go back to the public pool" do
    ExpireOffersJob.perform_now

    @reserved.reload
    assert_predicate @reserved, :approved?
    assert_nil @reserved.reserved_for
    assert_nil @reserved.reserved_until
  end

  test "the job is idempotent" do
    ExpireOffersJob.perform_now
    ExpireOffersJob.perform_now

    assert_predicate @due.reload, :expired?
    assert_predicate @reserved.reload, :approved?
  end
end
