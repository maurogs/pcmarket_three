module Api
  module V1
    # GET /api/v1/stores/:store_id/reviews — the store's public reviews
    # (hidden ones excluded, newest first), same rows the store page shows.
    class ReviewsController < BaseController
      skip_before_action :authenticate_token!

      PER_PAGE = 20

      def index
        @store = Store.visible.friendly.find(params[:store_id])
        @pagy, @reviews = pagy(
          @store.reviews.where(hidden_at: nil)
                .includes(:reviewer)
                .order(created_at: :desc, id: :desc),
          limit: PER_PAGE
        )
        set_link_header @pagy
      end
    end
  end
end
