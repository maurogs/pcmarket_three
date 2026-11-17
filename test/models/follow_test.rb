require "test_helper"

class FollowTest < ActiveSupport::TestCase
  test "follow records and counter-caches" do
    store = stores(:one)
    assert_equal 0, store.followers_count

    follow = Follow.create!(follower: users(:two), store: store)
    assert_equal 1, store.reload.followers_count

    follow.destroy
    assert_equal 0, store.reload.followers_count
  end

  test "a user cannot follow the same store twice" do
    Follow.create!(follower: users(:two), store: stores(:one))
    other = Follow.new(follower: users(:two), store: stores(:one))
    assert_not other.valid?
  end

  test "a user cannot follow their own store" do
    follow = Follow.new(follower: users(:one), store: stores(:one))
    assert_not follow.valid?
    assert_includes follow.errors[:store_id], I18n.t("activerecord.errors.models.follow.attributes.store_id.cannot_follow_own_store")
  end
end
