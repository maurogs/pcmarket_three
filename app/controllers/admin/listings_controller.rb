module Admin
  # Full-scope listing management: powerful filtered index (50/page), CSV
  # export of the same filtered set (streamed), edit of any field via
  # Listings::AdminUpdate, and destroy restricted to never-public states
  # (same rule the sellers see).
  class ListingsController < BaseController
    include Auditable

    PER_PAGE = 50

    before_action :set_listing, only: %i[show edit update destroy]

    def index
      @filter = params.slice(:status, :category, :country, :seller, :min_price, :max_price,
                             :created_from, :created_to, :featured, :has_photos, :q, :sort)
      @scope = Admin::ListingFilter.call(params)

      respond_to do |format|
        format.html { @pagy, @listings = pagy(@scope, limit: PER_PAGE) }
        format.csv do
          send_data Listings::CsvExport.build(@scope),
                    filename: "pcmarket-listings-#{Date.current}.csv",
                    type: "text/csv", disposition: "attachment"
        end
      end
    end

    def show
      @events = @listing.moderation_events.includes(:admin).recent
      @seller_counts = Listing.status_counts(Listing.where(user_id: @listing.user_id))
    end

    def edit
    end

    def update
      result = Listings::AdminUpdate.call(@listing, form_params)
      @listing = result.listing

      if result.saved?
        audit!(:edit_listing, @listing, changes: @listing.previous_changes.except("updated_at"))
        redirect_to admin_listing_path(@listing), notice: t(".updated", title: @listing.title)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      unless @listing.destroyable?
        @events = @listing.moderation_events.includes(:admin).recent
        @seller_counts = Listing.status_counts(Listing.where(user_id: @listing.user_id))
        flash.now[:alert] = t(".destroy_denied")
        render :show, status: :unprocessable_entity
        return
      end

      audit!(:delete_listing, @listing, title: @listing.title)
      @listing.destroy!
      redirect_to admin_listings_path, notice: t(".destroyed", title: @listing.title)
    end

    private

    def set_listing
      @listing = Listing.friendly.find(params[:id])
    end

    def form_params
      params.require(:listing).permit(
        :title, :description, :condition, :quantity, :price, :original_price,
        :shipping_price, :city, :region, :postal_code, :category_id, :status,
        :featured_until, :specs_json, label_ids: []
      ).to_h
    end
  end
end
