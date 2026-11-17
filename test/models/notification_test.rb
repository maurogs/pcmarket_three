require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    Notification.clear_unread_cache(@user)
  end

  test "unread_count_for caches and busts on create" do
    assert_equal 0, Notification.unread_count_for(@user)

    Notification.create!(user: @user, kind: "new_message", payload: { "conversation_id" => 1 })
    assert_equal 1, Notification.unread_count_for(@user)
  end

  test "mark_all_as_read_for clears the badge and makes rows read" do
    notification = Notification.create!(user: @user, kind: "new_message", payload: {})
    assert_not notification.read?

    Notification.mark_all_as_read_for(@user)
    assert notification.reload.read?
    assert_equal 0, Notification.unread_count_for(@user)
  end

  test "unsent_saved_search_matches only sees rows after the watermark" do
    search = SavedSearch.create!(user: @user, name: "GPUs")
    build_match = lambda do |created_at|
      n = Notification.create!(user: @user, kind: "saved_search_match",
                               payload: { "saved_search_id" => search.id, "listing_id" => listings(:gigabyte).id })
      n.update_columns(created_at: created_at)
      n
    end

    old = build_match.call(2.days.ago)
    search.update_columns(last_notified_at: 1.day.ago)
    old.reload

    recent = build_match.call(12.hours.ago)

    unsent = Notification.unsent_saved_search_matches(search)
    assert_not_includes unsent, old
    assert_includes unsent, recent
  end
end
