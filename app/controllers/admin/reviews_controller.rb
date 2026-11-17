module Admin
  # Review moderation (Phase 6b): the list plus "hide" (DELETE sets
  # hidden_at — the row is kept for the record) with a mandatory reason.
  # Hiding re-runs the store rating refresh (Review#refresh_store_rating).
  class ReviewsController < BaseController
    include Auditable

    def index
      scope = Review.includes(:reviewer, :store, :order).recent_first
      scope = scope.visible if params[:state] == "visible"
      scope = scope.hidden if params[:state] == "hidden"
      scope = scope.where(rating: params[:rating].to_i) if params[:rating].present?
      if params[:store].present?
        like = "%#{Review.sanitize_sql_like(params[:store].strip)}%"
        scope = scope.where(store: Store.where("name ILIKE :like OR slug ILIKE :like", like: like).select(:id))
      end
      @pagy, @reviews = pagy(scope, limit: 25)
    end

    def destroy
      review = Review.find(params[:id])
      reason = params[:reason].to_s.strip

      if reason.blank?
        redirect_to admin_reviews_path, alert: t(".reason_required")
        return
      end

      review.hide!
      audit!("review_hide", review, reason: reason, rating: review.rating, store_id: review.store_id)
      redirect_to admin_reviews_path, notice: t(".hidden")
    end
  end
end
