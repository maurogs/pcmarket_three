require "test_helper"

# Phase 8a: listing slug history — renaming a listing 301s old permalinks
# to the new one instead of 404-ing (FriendlyId history, same pattern the
# stores already used). Listings are created here rather than taken from
# fixtures because fixtures write the slug column directly, bypassing the
# FriendlyId bookkeeping that populates friendly_id_slugs.
class ListingSlugHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @listing = Listing.create!(
      user: users(:one), store: stores(:one), category: categories(:gpus),
      title: "History Test GPU One", description: "For slug history tests",
      price_cents: 10_000, condition: "brand_new"
    )
    @listing.update!(status: :approved, published_at: Time.current)
  end

  test "the old slug redirects permanently after a rename" do
    old_slug = @listing.slug
    @listing.update!(title: "History Test GPU Two")
    assert_not_equal old_slug, @listing.slug

    get "/listings/#{old_slug}"
    assert_response :moved_permanently
    assert_match @listing.slug, response.location

    get response.location
    assert_response :success
  end

  test "an unchanged title keeps the slug stable" do
    @listing.update!(price_cents: 12_000)
    assert_equal "history-test-gpu-one", @listing.slug

    get "/listings/history-test-gpu-one"
    assert_response :success
  end
end
