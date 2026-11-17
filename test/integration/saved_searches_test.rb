require "test_helper"

class SavedSearchesTest < ActionDispatch::IntegrationTest
  setup do
    @turbo = { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    @params = { q: "rtx", category: categories(:gpus).slug, min_price: "100", f: { "vram" => [ "12GB" ] } }
  end

  test "the results page offers a save-search form when filters are applied" do
    sign_in_as users(:two)
    get listings_path(@params)
    assert_response :success
    assert_select "form[action=?][method=?]", saved_searches_path, "post" do
      assert_select "input[name=?]", "name"
      assert_select "input[type=hidden][name=?]", "q"
      assert_select "input[type=hidden][name=?]", "category"
    end
  end

  test "save a search from the results page, then run it" do
    sign_in_as users(:two)

    post saved_searches_path(name: "Fast GPUs", **@params)
    assert_redirected_to saved_searches_path
    assert_equal "Fast GPUs", users(:two).saved_searches.reload.first.name

    get saved_searches_path
    assert_response :success
    assert_match "Fast GPUs", response.body

    # The run link replays the stored filters.
    get listings_path(users(:two).saved_searches.first.search_params.transform_keys(&:to_sym))
    assert_response :success
  end

  test "rejects over the per-user cap" do
    user = users(:two)
    sign_in_as user
    SavedSearch::MAX_PER_USER.times { |i| SavedSearch.create!(user: user, name: "S#{i}") }

    post saved_searches_path(name: "One too many", **@params)
    assert_redirected_to listings_path
    assert_equal SavedSearch::MAX_PER_USER, user.saved_searches.count
  end

  test "toggle e-mail alerts and delete via turbo streams" do
    sign_in_as users(:two)
    search = SavedSearch.create!(user: users(:two), name: "Toggled")

    patch saved_search_path(search), headers: @turbo
    assert search.reload.email_alerts
    assert_select "turbo-stream[action=?][target=?]", "replace", "saved_search_#{search.id}"

    patch saved_search_path(search), headers: @turbo
    assert_not search.reload.email_alerts

    delete saved_search_path(search), headers: @turbo
    assert_select "turbo-stream[action=?][target=?]", "remove", "saved_search_#{search.id}"
    assert_equal 0, users(:two).saved_searches.count
  end
end
