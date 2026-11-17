module Api
  module V1
    # POST /api/v1/offers/:offer_id/decline — the seller's no
    # (Offers::Decline). Same lookup discipline as the acceptance:
    # outsiders 404, the buyer 403, stale offers 409.
    class DeclinesController < BaseController
      before_action :verify_user!
      before_action :set_offer

      def create
        result = Offers::Decline.call(offer: @offer)

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
