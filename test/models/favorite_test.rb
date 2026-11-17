require "test_helper"

class FavoriteTest < ActiveSupport::TestCase
  test "counter cache updates on create and destroy" do
    listing = listings(:gigabyte)
    assert_equal 0, listing.favorites_count

    favorite = Favorite.create!(user: users(:two), listing: listing)
    assert_equal 1, listing.reload.favorites_count

    favorite.destroy
    assert_equal 0, listing.reload.favorites_count
  end

  test "a user cannot favorite the same listing twice" do
    Favorite.create!(user: users(:two), listing: listings(:gigabyte))
    other = Favorite.new(user: users(:two), listing: listings(:gigabyte))
    assert_not other.valid?
  end

  test "price_dropped? compares against the price captured on save" do
    favorite = Favorite.create!(user: users(:two), listing: listings(:gigabyte),
                                price_cents_at_save: listings(:gigabyte).price_cents)
    assert_not favorite.price_dropped?

    favorite.price_cents_at_save = favorite.listing.price_cents + 1_000
    assert favorite.price_dropped?
    assert_equal favorite.price_cents_at_save, favorite.saved_price.cents
  end
end
