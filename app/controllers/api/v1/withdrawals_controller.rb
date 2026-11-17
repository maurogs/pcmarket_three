module Api
  module V1
    # POST /api/v1/offers/:offer_id/withdrawal — the buyer takes their
    # offer back (Offers::Withdraw). Mirror image of the decline: only the
    # buyer may act, outsiders 404, the seller 403, stale offers 409.
    class WithdrawalsController < BaseController
      before_action :verify_user!
      before_action :set_offer

      def create
        result = Offers::Withdraw.call(offer: @offer)

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

          raise Api::V1::Forbidden unless @offer.buyer_id == current_user.id
        end

        def participant?
          @offer.buyer_id == current_user.id || @offer.listing.user_id == current_user.id
        end
    end
  end
end
