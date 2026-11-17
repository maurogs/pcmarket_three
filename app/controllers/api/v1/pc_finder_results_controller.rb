module Api
  module V1
    # GET /api/v1/pc_finder_results — quiz results through PcFinder::Search
    # (the same service as the web results page): published machines that
    # clear the required score, ordered by value.
    class PcFinderResultsController < BaseController
      skip_before_action :authenticate_token!
      before_action :authenticate_token_if_present

      def index
        @result = PcFinder::Search.new(finder_params, country_code: api_country_code,
                                       request: request).call
        set_link_header @result.pagy
      end

      private

      # Same slice the web form submits (PcFinderResultsController).
      def finder_params
        params.slice(:game, :games, :resolution, :fps, :budget, :tags, :page).permit!
      end
    end
  end
end
