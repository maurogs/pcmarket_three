module Api
  module V1
    # POST /api/v1/orders/:order_id/review — the buyer rates a completed
    # order (one review per order, the Review model's uniqueness + the
    # completed check here mirror ReviewsController). Rating validation is
    # the model's (422 with details via the base rescue).
    class OrderReviewsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        unless @order.completed? && @order.review.nil?
          return render_error(:conflict, :invalid_transition)
        end

        @review = @order.build_review(
          reviewer: current_user, seller: @order.seller, store: @order.seller.store,
          rating: params[:rating], body: params[:body]
        )
        @review.save!

        render :create, status: :created
      end

      private

        def set_order
          @order = current_user.orders.find(params[:order_id])
        end
    end
  end
end
