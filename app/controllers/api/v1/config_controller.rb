module Api
  module V1
    # GET /api/v1/config — everything a native client needs to render its
    # forms without hardcoding: the category tree, localized enum labels,
    # carrier list and the minimum app versions (Setting-backed; nil means
    # "no forced update"). Cached-ish cheap queries only.
    class ConfigController < BaseController
      skip_before_action :authenticate_token!
      before_action :authenticate_token_if_present

      def show
        fresh_when strong_etag: [ I18n.locale,
                                 Category.maximum(:updated_at), Setting.maximum(:updated_at) ]
        return if performed?

        @categories = Category.active.roots.ordered.includes(children: :children)
        @condition_labels = Listing.conditions.keys.index_with do |condition|
          Listing.human_attribute_name("condition/#{condition}")
        end
        @sort_labels = ListingSearch::SORTS.index_with do |sort|
          t("listings.results.sort_options.#{sort}")
        end
        @pc_finder_labels = {
          resolutions: Performance::FpsEstimator::RESOLUTIONS
                         .index_with { |r| t("pc_finders.show.resolutions.#{r}") },
          fps_targets: PcFinder::Search::FPS_TARGETS
                         .index_with { |fps| t("pc_finders.show.fps_targets.#{fps}") },
          budgets: PcFinder::Search::BUDGETS.keys
                         .index_with { |budget| t("pc_finders.show.budgets.#{budget}") },
          demands: %w[light medium heavy]
                         .index_with { |demand| t("pc_finders.show.demand.#{demand}") }
        }
        # Every known flag as a plain boolean, so the apps can gate their
        # own screens without a second round-trip.
        @flags = FeatureFlags::FEATURES.keys.index_with { |key| Flipper.enabled?(key) }
      end
    end
  end
end
