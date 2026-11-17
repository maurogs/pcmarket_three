require "test_helper"
require_relative "../../db/seeds/demo"

# Runs the Phase 9 demo seed (db/seeds/demo.rb) against the fixture-loaded
# test database inside the usual per-test transaction, so it never leaves
# demo rows behind. Network image calls are stubbed to fail, exercising the
# placeholder path; Openverse's throttle seam is set to zero.
class DemoSeedTest < ActiveSupport::TestCase
  DEMO_EMAIL_WHERE = [ "%@demo.pcmarket.test" ]

  setup do
    stub_request(:get, %r{api\.openverse\.org}).to_return(status: 500, body: "offline")
    DemoImages::Providers::Openverse.min_call_interval = 0
  end

  teardown do
    DemoImages::Providers::Openverse.min_call_interval = DemoImages::Providers::Openverse::MIN_CALL_INTERVAL
    DemoImages::Providers::Openverse.last_call_at = nil
  end

  test "the seed is idempotent and business stores carry valid CIFs" do
    DemoSeed.run!(count: 20)
    first_listings = demo_listings.count
    first_users = demo_users.count
    assert_equal 20, first_listings
    assert_empty photo_less_listings, "every demo listing must end with at least one photo"

    DemoSeed.run!(count: 20)
    assert_equal first_listings, demo_listings.count, "a second run must not duplicate listings"
    assert_equal first_users, demo_users.count, "a second run must not duplicate users"

    business_stores = Store.where(store_type: "business").where(user: demo_users)
    assert_equal 8, business_stores.count
    business_stores.each do |store|
      assert SpanishTaxIdValidator.valid?(store.vat_number),
             "store #{store.name} has invalid CIF #{store.vat_number}"
    end
  end

  private

  def demo_users
    User.where("email_address LIKE ?", DEMO_EMAIL_WHERE.first)
  end

  def demo_listings
    Listing.where(user: demo_users)
  end

  def photo_less_listings
    demo_listings.where.missing(:photos_attachments)
  end
end
