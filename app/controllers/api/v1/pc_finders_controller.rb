module Api
  module V1
    # GET /api/v1/pc_finder — the quiz metadata a native client needs:
    # games (with per-resolution required scores), resolution/FPS/budget
    # options, filter tags and their localized labels. Constants from the
    # PC Finder services are the single source of truth.
    class PcFindersController < BaseController
      skip_before_action :authenticate_token!

      def show
        render json: {
          pc_finder: {
            games: Performance::FpsEstimator.games.map { |game|
              scores = Performance::FpsEstimator::RESOLUTIONS.index_with do |resolution|
                Performance::FpsEstimator.required_scores(game[:slug], resolution)
              end.compact
              { slug: game[:slug], name: game[:name], demand: game[:demand],
                required_scores: scores }
            },
            resolutions: PcFinder::Search::RESOLUTIONS,
            fps_targets: PcFinder::Search::FPS_TARGETS,
            budgets: PcFinder::Search::BUDGETS.keys,
            filter_tags: PcFinder::Search::FILTER_TAGS,
            labels: {
              resolutions: PcFinder::Search::RESOLUTIONS
                           .index_with { |r| t("pc_finders.show.resolutions.#{r}") },
              fps_targets: PcFinder::Search::FPS_TARGETS
                             .index_with { |f| t("pc_finders.show.fps_targets.#{f}") },
              budgets: PcFinder::Search::BUDGETS.keys
                             .index_with { |b| t("pc_finders.show.budgets.#{b}") },
              demands: %w[light medium heavy]
                             .index_with { |d| t("pc_finders.show.demand.#{d}") }
            }
          }
        }
      end
    end
  end
end
