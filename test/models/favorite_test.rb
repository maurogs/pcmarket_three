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
end
