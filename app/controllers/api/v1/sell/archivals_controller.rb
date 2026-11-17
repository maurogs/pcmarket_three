module Api
  module V1
    module Sell
      # POST /api/v1/sell/listings/:listing_id/archival — Listing#archive!
      # (approved/rejected/draft → archived); invalid states 409 via the
      # base controller's InvalidTransition rescue.
      class ArchivalsController < BaseController
        before_action :verify_user!
        before_action :set_listing

        def create
          @listing.archive!
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
