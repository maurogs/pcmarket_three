module Api
  module V1
    module Sell
      # POST /api/v1/sell/listings/:listing_id/sale_mark — Listing#mark_sold!
      # (approved/reserved → sold), the off-platform "already sold" path.
      class SaleMarksController < BaseController
        before_action :verify_user!
        before_action :set_listing

        def create
          @listing.mark_sold!
          render :create
        end

        private

          def set_listing
            @listing = current_user.listings.friendly.find(params[:listing_id])
          end
      end
    end
  end
end
