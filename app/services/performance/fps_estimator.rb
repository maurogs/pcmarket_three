# Guesses the FPS a PC with a given Performance::Scorer score will get in a
# game from config/data/games.yml at a resolution. Results are ESTIMATES —
# every UI that shows one must label it as such.
#
# Assumptions (documented deliberately):
# * FPS scales roughly linearly with the composite score at fixed settings
#   (true enough between nearby tiers, wrong across CPU-bound vs GPU-bound
#   machines — accepted for a shopping aid).
# * games.yml stores the score required to hit 60 / 144 / 240 FPS per
#   resolution. We interpolate FPS piecewise-linearly through the points
#   (0,0), (req60,60), (req144,144), (req240,240) and extrapolate beyond
#   req240 with the last segment's slope. Because every game's required
#   scores rise with FPS and rise with resolution, the estimate is monotonic:
#   a higher score never lowers FPS, a higher resolution never raises it.
# * Input scores are capped at SCORE_CAP before estimating. games.yml's
#   required scores are themselves capped at that value (there is no PC
#   above the RTX 5090 reference), and extrapolating further would give
#   steeper high-resolution slopes than low-resolution ones — i.e. a
#   higher resolution could "beat" a lower one. Capping keeps the
#   monotonicity guarantee.
# * Output is clamped to 0..MAX_FPS and floored to an integer.
# * Unknown game slug / resolution returns nil (the caller hides the badge).
module Performance
  class FpsEstimator
    GAMES = YAML.load_file(Rails.root.join("config/data/games.yml")).freeze
    RESOLUTIONS = %w[1080p 1440p 2160p].freeze
    MAX_FPS = 500
    # Top of the Scorer scale (and of the required_score cap in games.yml);
    # scores above it are treated as equal, see the header note.
    SCORE_CAP = 1000

    # Points below req240 (score, fps).
    def self.estimate(score, game, resolution)
      req = required_scores(game, resolution)
      return nil if score.nil? || req.nil?

      points = [ [ 0, 0 ],
                 [ req["60"].to_i, 60 ],
                 [ req["144"].to_i, 144 ],
                 [ req["240"].to_i, 240 ] ]
      score = score.to_i
      return 0 if score <= 0
      score = SCORE_CAP if score > SCORE_CAP

      fps = interpolate(points, score)
      fps.clamp(0, MAX_FPS).floor
    end

    # The game entries for the quiz UI, in file order.
    def self.games
      GAMES.map { |slug, data| { slug: slug, name: data["name"], demand: data["demand"] } }
    end

    def self.required_scores(game, resolution)
      entry = GAMES[game.to_s]
      return nil if entry.nil? || !RESOLUTIONS.include?(resolution.to_s)

      entry.dig("required_score", resolution.to_s)
    end

    def self.interpolate(points, score)
      # Defensive: keep only strictly-increasing score points (equal-score
      # points collapse to the highest FPS one; bad data must not divide by 0).
      clean = []
      points.each do |x, y|
        if clean.any? && x <= clean[-1][0]
          clean[-1] = [ x, y ] if y > clean[-1][1]
        else
          clean << [ x, y ]
        end
      end

      clean.each_cons(2) do |(x1, y1), (x2, y2)|
        return y1 + (y2 - y1) * (score - x1).to_f / (x2 - x1) if score < x2
      end
      # Past the last known point: keep the final slope.
      x1, y1 = clean[-2]
      x2, y2 = clean[-1]
      y2 + (y2 - y1) * (score - x2).to_f / (x2 - x1)
    end
  end
end
