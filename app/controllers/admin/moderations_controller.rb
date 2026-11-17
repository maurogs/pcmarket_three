module Admin
  # The moderation queue: pending_review listings, oldest first, so the
  # backlog drains FIFO. show renders everything a moderator needs before
  # deciding (photos, specs, price context, seller history, duplicates,
  # risky-word flags).
  class ModerationsController < BaseController
    PER_PAGE = 20

    def index
      @filter_category = find_category
      @filter_country = params[:country].presence_in(Country.enabled.pluck(:code))
      @filter_seller = params[:seller].presence

      scope = pending_scope
      @pagy, @listings = pagy(scope.order(:created_at, :id), limit: PER_PAGE)
    end

    def show
      @listing = Listing.friendly.find(params[:id])
      @median_cents = Listing.category_median_price_cents(@listing)
      @duplicates = Listing.potential_duplicates_of(@listing)
      @seller = @listing.user
      @seller_counts = Listing.status_counts(Listing.where(user_id: @seller.id))
      @events = @listing.moderation_events.includes(:admin).recent

      queue = Listing.where(status: :pending_review).where.not(id: @listing.id)
      @prev_pending = queue.where("created_at < ?", @listing.created_at).order(created_at: :desc).first
      @next_pending = queue.where("created_at > ?", @listing.created_at).order(:created_at).first
    end

    private

    def pending_scope
      scope = Listing.where(status: :pending_review)
      scope = scope.where(category: @filter_category) if @filter_category
      scope = scope.in_country(@filter_country) if @filter_country
      scope = scope.where(user_id: User.where("username ILIKE ?", "%#{@filter_seller}%").select(:id)) if @filter_seller
      scope
    end

    def find_category
      return unless params[:category].present?

      Category.friendly.find(params[:category])
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
