require "test_helper"

class NotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    Notification.clear_unread_cache(@user)
  end

  test "index lists notifications with links and unread markers" do
    listing = listings(:gigabyte)
    Notification.create!(user: @user, kind: "price_drop",
                         payload: { "listing_id" => listing.id, "title" => listing.title,
                                    "price_cents" => 50_000, "currency" => "EUR" })
    conversation = Conversation.create!(listing: listing, buyer: @user, seller: users(:one))
    Notification.create!(user: @user, kind: "new_message",
                         payload: { "conversation_id" => conversation.id })
    Notification.clear_unread_cache(@user)

    sign_in_as @user
    get notifications_path
    assert_response :success
    assert_select "li", minimum: 2
    assert_select "a[href=?]", listing_path(listing)
    assert_select "a[href=?]", conversation_path(conversation)
    assert_select "form[action=?]", notifications_read_path # mark-all-read button
  end

  test "unknown kinds render a generic row without a link" do
    Notification.create!(user: @user, kind: "something_new", payload: {})

    sign_in_as @user
    get notifications_path
    assert_response :success
    assert_match "Something new", response.body
  end

  test "mark all read empties the unread badge" do
    sign_in_as @user
    Notification.create!(user: @user, kind: "new_message", payload: {})
    assert_equal 1, Notification.unread_count_for(@user)

    post notifications_read_path
    assert_redirected_to notifications_path
    assert_equal 0, Notification.unread_count_for(@user)
    assert @user.notifications.none?(&:unread?)
  end

  test "the header bell badge reflects the unread count" do
    sign_in_as @user
    get notifications_path
    assert_select "div#notifications-badge"

    Notification.create!(user: @user, kind: "new_message", payload: {})
    get notifications_path
    assert_select "div#notifications-badge", text: /1/
  end

  test "anonymous visitors cannot reach the notification centre" do
    get notifications_path
    assert_redirected_to new_session_path
  end
end
