# POST /offers/:offer_id/decline — the seller says no (pending offers only,
# guarded in the model). Seller-scoped lookup: foreign ids 404.
class DeclinesController < ApplicationController
  def create
    offer = Offer.for_seller(current_user).find(params[:offer_id])
    result = Offers::Decline.call(offer: offer)

    if result.offer
      redirect_to offer_decision_url(offer), notice: t(".declined")
    else
      redirect_to offer_decision_url(offer), alert: t("offers.decisions.stale")
    end
  end

  private

  def offer_decision_url(offer)
    conversation = offer.conversation
    conversation ? conversation_path(conversation) : offers_path
  end
end
