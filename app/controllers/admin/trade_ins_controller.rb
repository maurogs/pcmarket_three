module Admin
  class TradeInsController < BaseController
    include Auditable

    before_action :set_trade_in, only: %i[show update]

    def index
      @pagy, @trade_ins = pagy(TradeIn.recent_first, limit: 20)
    end

    def show
      # Self-service expiry keeps the admin view honest even for stale quotes.
      @trade_in.expire! if @trade_in.stale_quote?
    end

    def update
      @trade_in.transition_to!(params[:transition])
      audit!("trade_in_#{params[:transition]}", @trade_in)
      redirect_to admin_trade_in_path(@trade_in), notice: t(".updated")
    rescue TradeIn::InvalidTransition
      redirect_to admin_trade_in_path(@trade_in), alert: t(".invalid_transition")
    end

    private

    def set_trade_in
      @trade_in = TradeIn.find(params[:id])
    end
  end
end
