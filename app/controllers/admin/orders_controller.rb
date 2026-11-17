module Admin
  # Read-mostly order admin (Phase 6b). The only writes here are the audited
  # forced status transition (`update`) and internal notes (nested
  # Admin::NotesController) — the buyer/seller flow stays in the public
  # area.
  class OrdersController < BaseController
    include Auditable

    before_action :set_order, only: %i[show update]

    def index
      @pagy, @orders = pagy(OrderFilter.call(filter_params), limit: 25)
    end

    def show
      load_show_data
    end

    # Forced status transition — requires a reason, notifies both parties.
    def update
      result = Orders::ForceTransition.call(
        order: @order, to: params.dig(:order, :status), reason: params.dig(:order, :reason)
      )

      if result.error
        @failed_transition = true
        flash.now[:alert] = t(".errors.#{result.error}")
        load_show_data
        render :show, status: :unprocessable_entity
      else
        audit!("order_force_transition", @order,
               from: params[:from_status], to: params.dig(:order, :status),
               reason: params.dig(:order, :reason))
        redirect_to admin_order_path(@order), notice: t(".updated", number: @order.number)
      end
    end

    private

    def set_order
      @order = Order.find(params[:id])
    end

    def load_show_data
      @notes = @order.order_notes.includes(:admin).order(created_at: :desc, id: :desc)
      @events = AdminAuditLog.for_subject(@order).recent.limit(20)
      @conversation = @order.conversation
    end

    def filter_params
      params.slice(:status, :seller, :buyer, :provider, :from, :to, :q).permit!.to_h
    end
  end
end
