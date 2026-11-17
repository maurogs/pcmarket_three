# frozen_string_literal: true

require "test_helper"

class Performance::ScorerTest < ActiveSupport::TestCase
  test "composite score from known gpu and cpu models" do
    # rtx4080super 810 × 0.75 + ryzen79800x3d 920 × 0.25 = 837.5 → 838
    score = Performance::Scorer.score_for(
      gpu_model: "NVIDIA GeForce RTX 4080 Super",
      cpu_model: "AMD Ryzen 7 9800X3D"
    )
    assert_equal 838, score
  end

  test "normalization ignores brand words, punctuation and casing" do
    assert_equal Performance::Scorer.score_for(gpu_model: "rtx 4070 super", cpu_model: nil),
                 Performance::Scorer.score_for(gpu_model: "NVIDIA GeForce RTX-4070 SUPER", cpu_model: nil)
    assert_equal Performance::Scorer.gpu_score("AMD Radeon RX 6700 XT"), Performance::Scorer.gpu_score("rx6700xt")
    # Mobile/laptop parts score as their desktop sibling.
    assert_equal Performance::Scorer.gpu_score("NVIDIA GeForce RTX 4060 GPU (Laptop)"),
                 Performance::Scorer.gpu_score("RTX 4060")
  end

  test "unknown models score nil" do
    assert_nil Performance::Scorer.score_for(gpu_model: "Mystery GPU 9000", cpu_model: "Mystery CPU 9000")
    assert_nil Performance::Scorer.gpu_score(nil)
    assert_nil Performance::Scorer.cpu_score("")
  end

  test "one known component scores as-is when the other is unknown" do
    assert_equal 580, Performance::Scorer.score_for(gpu_model: "RTX 4070", cpu_model: "Unknown Chip")
    assert_equal 510, Performance::Scorer.score_for(gpu_model: nil, cpu_model: "Intel Core i5-12400F")
  end

  test "score_from_specs reads the specs hash" do
    specs = { "gpu_model" => "AMD Radeon RX 6700 XT", "cpu_model" => "AMD Ryzen 7 5800X3D" }
    # rx6700xt 450 × 0.75 + ryzen75800x3d 640 × 0.25 = 497.5 → 498
    assert_equal 498, Performance::Scorer.score_from_specs(specs)
  end

  test "fixture gaming PC scores match what the scorer computes" do
    [
      listings(:beast_rtx4080s), listings(:mid_rgb_build),
      listings(:budget_3060_build), listings(:value_5800x3d_build)
    ].each do |listing|
      expected = Performance::Scorer.score_from_specs(listing.specs)
      assert_equal expected, listing.performance_score,
                   "fixture #{listing.to_param} performance_score drifted from the scorer"
    end
  end

  test "score recomputes when specs change and is nulled for unknown models" do
    listing = listings(:budget_3060_build)
    assert_equal 383, listing.performance_score

    listing.update!(specs: listing.specs.merge("gpu_model" => "NVIDIA GeForce RTX 5090"))
    # rtx5090 1000 × 0.75 + i512400f 510 × 0.25 = 877.5 → 878
    assert_equal 878, listing.performance_score

    listing.update!(specs: { "gpu_model" => "NoName GPU", "cpu_model" => "NoName CPU" })
    assert_nil listing.performance_score
  end

  test "listings outside the scorable categories stay unscored" do
    listing = listings(:as_new) # a GPU listing, not a PC
    assert_nil listing.performance_score

    listing.update!(title: "Barely used RTX 4060 (updated)")
    assert_nil listing.performance_score
  end
end
