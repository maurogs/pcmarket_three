require "test_helper"

# Regression guard for the Prosopite N+1s found on the public listing paths:
# cards of store-less sellers call User#display_name (which reads the user's
# store), and the show pages / API build one ActiveStorage variant per photo.
# Prosopite.raise is on in the test env (config/environments/test.rb) and the
# integration-session scan wraps every request (test/test_helper.rb), so ANY
# remaining N+1 makes the GETs below raise instead of merely logging.
class ListingNPlusOneTest < ActionDispatch::IntegrationTest
  # 1x1 RGBA PNG (validated with vips) — a real image so blob identification
  # (and any variant preprocessing) behaves exactly like production photos.
  TINY_PNG = [
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489" \
    "0000000d4944415478da6360000002000100ffff03000006000557bfabd4" \
    "0000000049454e44ae426082"
  ].join.then { |hex| [ hex ].pack("H*") }

  setup do
    @listings = 3.times.map { |i| make_approved_listing_without_store(i) }
  end

  test "listings index, listing show and the API show run without N+1s" do
    get listings_path
    assert_response :success

    listing = @listings.first
    get listing_path(listing)
    assert_response :success

    get api_v1_listing_path(listing)
    assert_response :success
  end

  private

  def make_approved_listing_without_store(index)
    user = User.create!(
      email_address: "nostore#{index}@example.com", username: "nostore#{index}",
      password: "password123", confirmed_at: Time.current
    )
    listing = Listing.new(
      user: user, category: categories(:gpus),
      title: "N+1 Regression Listing #{index}", description: "Store-less seller, three photos",
      price_cents: 10_000 + index, condition: "used_good"
    )
    3.times do |photo_index|
      listing.photos.attach(io: StringIO.new(TINY_PNG),
                            filename: "photo-#{photo_index}.png", content_type: "image/png")
    end
    raise "listing invalid: #{listing.errors.full_messages}" unless listing.save

    listing.update!(status: :approved, published_at: Time.current)
    listing
  end
end
