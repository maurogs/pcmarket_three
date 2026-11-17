# frozen_string_literal: true

require "test_helper"

class PcFinderTest < ActionDispatch::IntegrationTest
  test "the quiz page renders with game options and no params needed" do
    get pc_finder_path
    assert_response :success
    assert_select "h1", text: I18n.t("pc_finders.show.title")
    # every quiz game appears as a checkbox, and the form targets the results page
    Performance::FpsEstimator::GAMES.each_key do |slug|
      assert_select "input[type=checkbox][name='games[]'][value=?]", slug
    end
    assert_select "form[action=?]", pc_finder_results_path
  end

  test "the 'best PCs for' strip shows a sample machine per game" do
    get pc_finder_path
    assert_response :success
    assert_match I18n.t("pc_finders.show.best_for"), response.body
    # fortnite @1440p/144 → the beast is the sample for it
    assert_match listings(:beast_rtx4080s).title, response.body
  end

  test "results render for a quiz without params" do
    get pc_finder_results_path
    assert_response :success
    assert_select "h1"
    assert_match I18n.t("pc_finder_results.index.count", count: 4), response.body
    all_pc_slugs = [ "custom-rtx-4080-super-gaming-pc", "mid-range-ryzen-5-gaming-desktop",
                     "budget-rtx-3060-starter-pc", "ryzen-7-5800x3d-value-build" ]
    all_pc_slugs.each do |slug|
      assert_select "a[href=?]", listing_path(slug)
    end
  end

  test "results page is browser-cached only, anonymous and signed-in" do
    get pc_finder_results_path
    assert_response :success
    cache_control = response.headers["Cache-Control"]
    assert_match(/\bprivate\b/, cache_control)
    assert_no_match(/\bpublic\b/, cache_control)
    assert_match(/max-age=0\b/, cache_control)
    assert_match(/must-revalidate\b/, cache_control)

    sign_in_as users(:one)
    get pc_finder_results_path
    assert_response :success
    assert_match(/\bprivate\b/, response.headers["Cache-Control"])
    assert_no_match(/\bpublic\b/, response.headers["Cache-Control"])
    assert_no_match(/max-age=60\b/, response.headers["Cache-Control"])
  end

  test "results honour the quiz answers and badge the best match" do
    get pc_finder_results_path(game: "fortnite", resolution: "1080p", fps: "144")
    assert_response :success
    assert_match I18n.t("pc_finder_results.index.required_score", score: 480), response.body
    assert_select "a[href=?]", listing_path(listings(:beast_rtx4080s).slug)
    assert_select "a[href=?]", listing_path(listings(:budget_3060_build).slug), count: 0
    # value-best first → badged
    assert_match I18n.t("pc_finder_results.result.best_match"), response.body
    # applied budget chips only when a band was chosen: not here
    assert_select "a[href*='budget=']", count: 0
  end

  test "empty results offer relaxation links" do
    get pc_finder_results_path(game: "cyberpunk-2077", resolution: "2160p", fps: "240")
    assert_response :success
    assert_match I18n.t("pc_finder_results.index.empty_title"), response.body
    assert_match I18n.t("pc_finder_results.index.suggestions.lower_fps"), response.body
    assert_match I18n.t("pc_finder_results.index.suggestions.cheaper_budget"), response.body
  end

  test "page 2 of results renders too" do
    get pc_finder_results_path(page: 2)
    assert_response :success
  end
end
