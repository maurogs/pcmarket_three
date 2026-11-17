class TradeInQuotesController < ApplicationController
  allow_unauthenticated_access only: %i[new create show]

  before_action :ensure_feature_enabled
  before_action :set_quote, only: :show

  def new
    @gpu_models = TradeIns::Quote.models("gpu")
    @cpu_models = TradeIns::Quote.models("cpu")
    @gpu_examples = TradeIns::Quote.example_rows("gpu")
    @cpu_examples = TradeIns::Quote.example_rows("cpu")
  end

  def create
    @gpu_models = TradeIns::Quote.models("gpu")
    @cpu_models = TradeIns::Quote.models("cpu")
    @gpu_examples = []
    @cpu_examples = []

    result = TradeIns::Quote.call(
      component_type: params[:model].to_s.split(":", 2).first,
      model: params[:model].to_s.split(":", 2).second,
      condition: params[:condition],
      has_box: params[:has_box] == "1"
    )

    if result.success?
      redirect_to trade_in_quote_path(result.record)
    else
      flash.now[:alert] = t(".errors.#{result.error}")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # A stale offer marks itself expired the moment anyone opens it.
    @quote.expire! if @quote.stale_quote?
  end

  private

  def ensure_feature_enabled
    head :not_found unless Flipper.enabled?(:sell_to_us)
  end

  def set_quote
    @quote = TradeIn.find(params[:id])
  end
end
