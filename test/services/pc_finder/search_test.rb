# frozen_string_literal: true

require "test_helper"

class PcFinder::SearchTest < ActiveSupport::TestCase
  # Fixture gaming PCs: beast 838/1899€, mid 560/109.9€, budget 383/64.9€, value 498/59.9€.
  ALL_PC_SLUGS = [ "custom-rtx-4080-super-gaming-pc", "mid-range-ryzen-5-gaming-desktop",
                   "budget-rtx-3060-starter-pc", "ryzen-7-5800x3d-value-build" ].freeze

  def slugs(results)
    results.records.map(&:slug)
  end

  test "no filters: every published PC in the finder categories, value order" do
    results = PcFinder::Search.new({}, country_code: "ES").call
    assert_equal ALL_PC_SLUGS.sort, slugs(results).sort
    # value = score per euro → the 5800X3D build tops the list, beast last
    assert_equal "ryzen-7-5800x3d-value-build", results.records.first.slug
    assert_equal "custom-rtx-4080-super-gaming-pc", results.records.last.slug
    assert_nil results.required_score
    assert_empty results.suggestions
  end

  test "non-PC categories never show up in the finder" do
    results = PcFinder::Search.new({}, country_code: "ES").call
    refute_includes slugs(results), listings(:as_new).slug
  end

  test "required score is the worst-case over the chosen games" do
    # fortnite 1080p/144 needs 480; cyberpunk-2077 1080p/144 needs much more.
    search = PcFinder::Search.new({ games: [ "fortnite", "cyberpunk-2077" ], resolution: "1080p", fps: "144" })
    fortnite = Performance::FpsEstimator.required_scores("fortnite", "1080p")["144"]
    cyberpunk = Performance::FpsEstimator.required_scores("cyberpunk-2077", "1080p")["144"]
    assert_equal [ fortnite, cyberpunk ].max, search.required_score

    results = search.call
    refute_empty results.records
    results.records.each do |listing|
      assert_operator listing.performance_score, :>=, search.required_score
    end
  end

  test "score bar filters out PCs that cannot clear the games" do
    # fortnite @1080p/144 → 480: budget_3060_build (383) must fall out.
    results = PcFinder::Search.new({ games: [ "fortnite" ], resolution: "1080p", fps: "144" }).call
    assert_equal [ "ryzen-7-5800x3d-value-build", "mid-range-ryzen-5-gaming-desktop",
                   "custom-rtx-4080-super-gaming-pc" ], slugs(results)
    refute_includes slugs(results), "budget-rtx-3060-starter-pc"
  end

  test "more than MAX_GAMES games keeps only the first three" do
    search = PcFinder::Search.new({ games: %w[fortnite valorant minecraft gta-v] })
    assert_equal %w[fortnite valorant minecraft], search.games
  end

  test "combined game param (quiz single pick) also counts" do
    results = PcFinder::Search.new({ game: "fortnite", resolution: "1080p", fps: "144" }).call
    assert_equal 480, results.required_score
    refute_includes slugs(results), "budget-rtx-3060-starter-pc"
  end

  test "budget band restricts price" do
    results = PcFinder::Search.new({ budget: "under_700" }).call
    assert_equal [ "ryzen-7-5800x3d-value-build", "budget-rtx-3060-starter-pc" ].sort, slugs(results).sort

    results = PcFinder::Search.new({ budget: "1200_2000" }).call
    assert_equal [ "custom-rtx-4080-super-gaming-pc" ], slugs(results)
  end

  test "invalid budget or unknown slugs are dropped silently" do
    results = PcFinder::Search.new({ budget: "banana", games: [ "zelda" ] }).call
    assert_nil results.filters[:budget]
    assert_empty results.filters[:games]
    assert_equal ALL_PC_SLUGS.sort, slugs(results).sort
  end

  test "optional seller tags are AND-ed" do
    results = PcFinder::Search.new({ tags: [ "competitive" ] }).call
    assert_equal [ "custom-rtx-4080-super-gaming-pc" ], slugs(results)

    results = PcFinder::Search.new({ tags: [ "competitive", "air-cooling" ] }).call
    assert_predicate results, :empty?
    assert_includes results.suggestions.map { |s| s[:key] }, "drop_tags"

    results = PcFinder::Search.new({ tags: [ "air-cooling" ] }).call
    assert_equal [ "ryzen-7-5800x3d-value-build" ], slugs(results)
  end

  test "zero results suggest useful relaxations" do
    results = PcFinder::Search.new(
      { games: [ "cyberpunk-2077" ], resolution: "2160p", fps: "240", budget: "under_700", tags: [ "competitive" ] }
    ).call
    assert_predicate results, :empty?
    keys = results.suggestions.map { |s| s[:key] }
    assert_equal [ "lower_fps", "raise_budget", "drop_tags" ], keys
  end

  test "cheaper_budget suggestion appears when no band is set" do
    results = PcFinder::Search.new({ games: [ "cyberpunk-2077" ], resolution: "2160p", fps: "240" }).call
    assert_predicate results, :empty?
    assert_includes results.suggestions.map { |s| s[:key] }, "cheaper_budget"
  end

  test "pagination slices records and exposes page links" do
    results = PcFinder::Search.new({}, country_code: "ES").call(limit: 2)
    assert_equal 2, results.records.size
    assert_equal 4, results.total_count
    assert_equal 2, results.pagy.pages

    page2 = PcFinder::Search.new({ page: 2 }, country_code: "ES").call(limit: 2)
    assert_equal 2, page2.records.size
    assert_empty (results.records.map(&:id) & page2.records.map(&:id))
  end

  test "sample_for picks the best machine clearing the game bar" do
    # fortnite @1440p/144 needs 700 — only the 838-score beast clears it.
    listing = PcFinder::Search.sample_for("fortnite", country_code: "ES")
    assert_equal "custom-rtx-4080-super-gaming-pc", listing.slug
  end
end
