module Api
  module V1
    module Sell
      # POST /api/v1/sell/listings/:listing_id/submission — push a
      # draft/rejected listing into the moderation queue. Listings::Submit
      # owns the transition and the admin notifications; the model's
      # InvalidTransition becomes a 409 through the base controller rescue.
      class SubmissionsController < BaseController
        before_action :verify_user!
        before_action :set_listing

        def create
          Listings::Submit.new(@listing).call
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
