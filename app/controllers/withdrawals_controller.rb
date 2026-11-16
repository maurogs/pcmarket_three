# POST /offers/:offer_id/withdrawal — the buyer takes their offer back.
# Scoped to current_user.offers, so nobody withdraws someone else's offer.
class WithdrawalsController < ApplicationController
  def create
    offer = Offer.sent_by(current_user).find(params[:offer_id])
    result = Offers::Withdraw.call(offer: offer)

    if result.offer
      redirect_to offer_decision_url(offer), notice: t(".withdrawn")
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
