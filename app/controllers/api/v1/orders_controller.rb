module Api
  module V1
    # Order inbox for both sides: ?role=buyer (purchases, the web /orders)
    # or ?role=seller (sales, the web /sell/sales). show accepts either
    # party; anyone else 404s — existence of other people's order ids is
    # never confirmed.
    class OrdersController < BaseController
      before_action :verify_user!

      def index
        scope = params[:role] == "seller" ? current_user.sales : current_user.orders
        @pagy, @orders = pagy(
          scope.recent.includes(:buyer, :seller, order_items: :listing),
          limit: page_size
        )
        set_link_header @pagy
      end

      def show
        @order = visible_order_scope.find(params[:id])
      end

      private

        def visible_order_scope
          Order.where("orders.buyer_id = :me OR orders.seller_id = :me", me: current_user.id)
        end
    end
  end
end
