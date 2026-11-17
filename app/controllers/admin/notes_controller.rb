module Admin
  # Internal order notes (Phase 6b): short admin-only records on the order
  # page. Bodies never reach buyer or seller.
  class NotesController < BaseController
    include Auditable

    before_action :set_order

    def create
      note = @order.order_notes.build(admin: Current.user, body: params.dig(:order_note, :body))

      if note.save
        audit!("order_note_create", note, order_number: @order.number)
        redirect_to admin_order_path(@order), notice: t(".created")
      else
        flash[:alert] = note.errors.full_messages.to_sentence
        redirect_to admin_order_path(@order)
      end
    end

    def destroy
      note = @order.order_notes.find(params[:id])
      note.destroy!
      audit!("order_note_destroy", note, order_number: @order.number)
      redirect_to admin_order_path(@order), notice: t(".destroyed")
    end

    private

    def set_order
      @order = Order.find(params[:order_id])
    end
  end
end
