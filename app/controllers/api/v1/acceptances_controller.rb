module Api
  module V1
    # POST /api/v1/offers/:offer_id/acceptance — the seller's yes
    # (Offers::Accept reserves the listing and auto-declines the rest).
    # Non-participants 404, participants who are not the seller 403; an
    # offer that stopped being pending under the client 409s.
    class AcceptancesController < BaseController
      before_action :verify_user!
      before_action :set_offer

      def create
        result = Offers::Accept.call(offer: @offer)

        if result.offer
          @offer = result.offer
          render :create
        else
          render_error(:conflict, :stale_transition)
        end
      end

      private

        def set_offer
          @offer = Offer.includes(:buyer, listing: :user).find(params[:offer_id])
          raise ActiveRecord::RecordNotFound unless participant?

          raise Api::V1::Forbidden unless @offer.listing.user_id == current_user.id
        end

        def participant?
          @offer.buyer_id == current_user.id || @offer.listing.user_id == current_user.id
        end
    end
  end
end
