module Admin
  # Dispute resolution wizard (nested singular resource on disputes#show):
  # POST creates the outcome via Disputes::Resolve — refund (full/partial,
  # Stripe-backed when the order has a payment_reference) or release to the
  # seller. Every attempt is audited, including refusals.
  class ResolutionsController < BaseController
    include Auditable

    before_action :set_order

    def new
      @payment_cents = @order.total_cents
    end

    def create
      action = params.dig(:resolution, :action)
      amount_cents = params.dig(:resolution, :amount).presence &&
                     Listings::FormAttributes.euros_to_cents(params.dig(:resolution, :amount))

      result = Disputes::Resolve.call(order: @order, action: action, amount_cents: amount_cents)

      if result.error
        audit!("dispute_resolution_failed", @order, action: action, error: result.error)
        flash.now[:alert] = t("admin.resolutions.create.errors.#{result.error}")
        @payment_cents = @order.total_cents
        render :new, status: :unprocessable_entity
      else
        audit!("dispute_resolution", @order, action: action,
               amount_cents: @order.reload.refund_cents)
        redirect_to admin_dispute_path(@order), notice: t(".resolved.#{action}")
      end
    end

    private

    def set_order
      @order = Order.find(params[:dispute_id])
    end
  end
end
