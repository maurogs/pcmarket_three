require "test_helper"

class FavoritesTest < ActionDispatch::IntegrationTest
  setup do
    @listing = listings(:gigabyte)
    @turbo = { "Accept" => "text/vnd.turbo-stream.html, text/html" }
  end

  test "heart button appears on the listing page for guests as a sign-in link" do
    get listing_path(@listing)
    assert_response :success
    assert_select "div#favorite_button_#{@listing.id} a[href=?]", new_session_path
  end

  test "guests are bounced to sign-in with the destination remembered" do
    get favorites_path
    assert_redirected_to new_session_path

    get listing_path(@listing)
    assert_response :success
  end

  test "create, duplicate and destroy via turbo streams" do
    sign_in_as users(:two)

    post favorites_path(listing_id: @listing.id), headers: @turbo
    assert_equal 1, users(:two).favorites.count

    post favorites_path(listing_id: @listing.id), headers: @turbo
    assert_equal 1, users(:two).favorites.count, "favouriting twice is idempotent"

    favorite = users(:two).favorites.find_by(listing: @listing)
    assert_equal @listing.price_cents, favorite.price_cents_at_save

    delete favorite_path(favorite), headers: @turbo
    assert_select "turbo-stream[action=?][target=?]", "remove", "favorite_#{@listing.id}"
    assert_select "turbo-stream[action=?][target=?]", "replace", "favorite_button_#{@listing.id}"
    assert_equal 0, users(:two).favorites.count
  end

  test "wishlist page shows the percentage the price dropped since saving" do
    user = users(:two)
    sign_in_as user
    Favorite.create!(user: user, listing: @listing, price_cents_at_save: 60_000)
    @listing.update!(price_cents: 45_000)

    get favorites_path
    assert_response :success
    assert_select "div#favorite_#{@listing.id}"
    assert_match "25%", response.body
  end

  test "anonymous visitors are bounced to sign-in" do
    get favorites_path
    assert_redirected_to new_session_path
  end
end
