# POST /offers/:offer_id/acceptance — the seller says yes. The offer is
# looked up through Offer.for_seller, so a foreign "seller" 404s no matter
# which id they post. Reservation + auto-declining the other pending offers
# lives in Offers::Accept.
class AcceptancesController < ApplicationController
  def create
    offer = Offer.for_seller(current_user).find(params[:offer_id])
    result = Offers::Accept.call(offer: offer)

    if result.offer
      redirect_to offer_decision_url(offer), notice: t(".accepted")
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
