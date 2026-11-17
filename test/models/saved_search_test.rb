require "test_helper"

class SavedSearchTest < ActiveSupport::TestCase
  test "new_from_search maps browse params onto query, category and filters" do
    category = categories(:gpus)

    search = SavedSearch.new_from_search(
      user: users(:two),
      name: "Cheap GPUs",
      search_filters: ActionController::Parameters.new(
        q: "rtx", category: category.slug, min_price: "100", max_price: "800",
        condition: "used_good", f: { "gpu_chipset" => [ "rtx_3070" ] },
        labels: [ "warranty" ], sort: "newest", page: "2"
      ).permit!
    )

    assert search.save, search.errors.full_messages.to_sentence
    assert_equal "rtx", search.query
    assert_equal category, search.category
    assert_equal({ "min_price" => "100", "max_price" => "800", "condition" => "used_good",
                   "labels" => [ "warranty" ] }, search.filters.slice("min_price", "max_price", "condition", "labels"))
    assert_not search.filters.key?("sort")
    assert_not search.email_alerts, "alerts default off"
  end

  test "search_params rebuilds the ListingSearch input" do
    search = SavedSearch.new_from_search(
      user: users(:two), name: "Used GPUs",
      search_filters: ActionController::Parameters.new(q: "gpu", category: categories(:gpus).slug, min_price: "50").permit!
    )
    search.save!

    params = search.search_params
    assert_equal "gpu", params["q"]
    assert_equal categories(:gpus).slug, params["category"]
    assert_equal "50", params["min_price"]
  end

  test "a user is capped at MAX_PER_USER saved searches" do
    SavedSearch::MAX_PER_USER.times do |i|
      SavedSearch.create!(user: users(:two), name: "Search #{i}")
    end

    search = SavedSearch.new(user: users(:two), name: "One too many")
    assert_not search.valid?
    assert_includes search.errors.details[:base].map { |d| d[:error] }, :saved_search_limit
  end

  test "blank names are rejected" do
    assert_not SavedSearch.new(user: users(:two), name: " ").valid?
  end
end
