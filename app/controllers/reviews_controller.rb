# POST /orders/:order_id/review — one review per completed order (the
# Review model enforces the order-level uniqueness; the buyer must own
# the order and it must be completed). Review#refresh_store_rating!
# keeps the store rating current.
class ReviewsController < ApplicationController
  before_action :set_order

  def new
    unless reviewable?
      return redirect_to order_path(@order), alert: t(".not_reviewable")
    end

    @review = @order.build_review(reviewer: current_user)
  end

  def create
    unless reviewable?
      return redirect_to order_path(@order), alert: t(".not_reviewable")
    end

    @review = @order.build_review(
      reviewer: current_user, seller: @order.seller, store: @order.seller.store,
      **review_params
    )

    if @review.save
      redirect_to order_path(@order), notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = current_user.orders.find(params[:order_id])
  end

  def reviewable?
    @order.completed? && @order.review.nil?
  end

  def review_params
    params.require(:review).permit(:rating, :body)
  end
end
