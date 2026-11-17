class TradeInAcceptancesController < ApplicationController
  before_action :ensure_feature_enabled

  # POST /sell-to-us/:trade_in_quote_id/acceptance (authenticated). The quote
  # may have been created anonymously — Accept stamps the current user and
  # rejects stale or already-claimed rows.
  def create
    @quote = TradeIn.find(params[:trade_in_quote_id])

    case TradeIns::Accept.call(trade_in: @quote, user: current_user)
    when :ok
      redirect_to sell_dashboard_path, notice: t(".accepted")
    when :expired
      redirect_to trade_in_quote_path(@quote), alert: t(".expired")
    else
      redirect_to trade_in_quote_path(@quote), alert: t(".invalid")
    end
  end

  private

  def ensure_feature_enabled
    head :not_found unless Flipper.enabled?(:sell_to_us)
  end
end
