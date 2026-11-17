require "test_helper"

class FollowsTest < ActionDispatch::IntegrationTest
  setup do
    @store = stores(:one) # owned by users(:one)
    @turbo = { "Accept" => "text/vnd.turbo-stream.html, text/html" }
  end

  test "store page shows the follow button and follower count" do
    sign_in_as users(:two)
    get store_path(@store)
    assert_response :success
    assert_select "div#follow_button_#{@store.id} button"
    assert_select "span#follower_count_#{@store.id}"
  end

  test "own store page renders no follow button" do
    sign_in_as users(:one)
    get store_path(@store)
    assert_response :success
    assert_select "div#follow_button_#{@store.id} button", count: 0
  end

  test "follow and unfollow via turbo streams" do
    sign_in_as users(:two)

    post store_follow_path(@store), headers: @turbo
    assert_equal 1, @store.reload.followers_count
    assert_select "turbo-stream[action=?][target=?]", "replace", "follow_button_#{@store.id}"
    assert_select "turbo-stream[action=?][target=?]", "replace", "follower_count_#{@store.id}"

    delete store_follow_path(@store), headers: @turbo
    assert_equal 0, @store.reload.followers_count
  end

  test "following your own store is refused" do
    sign_in_as users(:one)

    assert_no_difference -> { Follow.count } do
      post store_follow_path(@store), headers: @turbo
    end
    assert_select "turbo-stream[action=?][target=?]", "update", "follow_error_#{@store.id}"
  end

  test "hidden stores have no follow target" do
    sign_in_as users(:two)
    @store.update!(hidden: true)

    post store_follow_path(@store), headers: @turbo
    assert_response :not_found
  end
end
