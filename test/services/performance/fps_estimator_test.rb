# frozen_string_literal: true

require "test_helper"

class Performance::FpsEstimatorTest < ActiveSupport::TestCase
  GAME = "cyberpunk-2077"

  test "returns exactly the target FPS at each reference score" do
    Performance::FpsEstimator::RESOLUTIONS.each do |resolution|
      req = Performance::FpsEstimator.required_scores("fortnite", resolution)
      assert_equal 60, Performance::FpsEstimator.estimate(req["60"], "fortnite", resolution)
      assert_equal 144, Performance::FpsEstimator.estimate(req["144"], "fortnite", resolution)
      assert_equal 240, Performance::FpsEstimator.estimate(req["240"], "fortnite", resolution)
    end
  end

  test "estimates are monotonically non-decreasing with the score" do
    Performance::FpsEstimator::GAMES.each_key do |slug|
      Performance::FpsEstimator::RESOLUTIONS.each do |resolution|
        prev = -1
        (0..1200).step(10) do |score|
          fps = Performance::FpsEstimator.estimate(score, slug, resolution)
          assert_operator fps, :>=, prev, "#{slug} #{resolution} fps dipped at score #{score}"
          prev = fps
        end
      end
    end
  end

  test "higher resolution never estimates more FPS than lower resolution" do
    (0..1200).step(25) do |score|
      low = Performance::FpsEstimator.estimate(score, GAME, "1080p")
      mid = Performance::FpsEstimator.estimate(score, GAME, "1440p")
      high = Performance::FpsEstimator.estimate(score, GAME, "2160p")
      assert_operator mid, :<=, low, "#{score}: 1440p beat 1080p"
      assert_operator high, :<=, mid, "#{score}: 2160p beat 1440p"
    end
  end

  test "zero and negative scores bottom out at 0 fps" do
    assert_equal 0, Performance::FpsEstimator.estimate(0, GAME, "1080p")
    assert_equal 0, Performance::FpsEstimator.estimate(-50, GAME, "1080p")
  end

  test "clamps at MAX_FPS for absurd scores" do
    assert_equal Performance::FpsEstimator::MAX_FPS, Performance::FpsEstimator.estimate(100_000, "league-of-legends", "1080p")
  end

  test "interpolates between reference points and floors" do
    req = Performance::FpsEstimator.required_scores("fortnite", "1080p")
    mid_score = (req["60"] + req["144"]) / 2
    fps = Performance::FpsEstimator.estimate(mid_score, "fortnite", "1080p")
    assert_operator fps, :>, 60
    assert_operator fps, :<, 144
    assert_equal fps, fps.floor # integer result
  end

  test "unknown game or resolution returns nil" do
    assert_nil Performance::FpsEstimator.estimate(500, "not-a-game", "1080p")
    assert_nil Performance::FpsEstimator.estimate(500, "fortnite", "8k")
    assert_nil Performance::FpsEstimator.estimate(nil, "fortnite", "1080p")
  end

  test "games list exposes slug, name and demand in file order" do
    games = Performance::FpsEstimator.games
    assert_equal Performance::FpsEstimator::GAMES.keys, games.map { |g| g[:slug] }
    assert_equal "Fortnite", games.first[:name]
    assert_includes %w[light medium heavy], games.first[:demand]
  end
end
