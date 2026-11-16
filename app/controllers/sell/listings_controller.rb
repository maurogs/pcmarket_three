module Sell
  # Seller's own listings: "My listings" plus the create/edit form. Every
  # lookup is scoped through current_user.listings, so another seller's
  # listing id raises RecordNotFound (404) rather than leaking or being
  # editable.
  class ListingsController < BaseController
    TABS = %w[all draft pending_review approved rejected sold archived].freeze
    PER_PAGE = 20

    before_action :set_listing, only: %i[edit update destroy]

    def index
      @tab = params[:tab].presence_in(TABS) || "all"
      assign_index_data
    end

    def new
      @listing = current_user.listings.new(quantity: 1, shipping_available: true, condition: "used_good")
      assign_category_state
    end

    def create
      result = Listings::Create.new(current_user, form_params).call(submit: submitting?)
      @listing = result.listing

      if result.saved?
        notice = result.submitted? ? t(".submitted") : t(".draft_saved")
        redirect_to edit_sell_listing_path(@listing), notice: notice
      else
        assign_category_state(form_params)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      assign_category_state
    end

    def update
      result = Listings::Update.new(@listing, form_params).call(submit: submitting?)
      @listing = result.listing

      if result.saved?
        notice = if result.re_reviewed?
                   t(".re_reviewed")
        elsif result.submitted?
                   t(".submitted")
        else
                   t(".updated")
        end
        redirect_to edit_sell_listing_path(@listing), notice: notice
      else
        assign_category_state(form_params)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tab = params[:tab].presence_in(TABS) || "all"
      unless @listing.destroyable?
        assign_index_data
        flash.now[:alert] = t(".destroy_denied")
        render :index, status: :unprocessable_entity
        return
      end

      @listing.destroy!
      redirect_to sell_listings_path(tab: @tab), notice: t(".destroyed")
    end

    private

    def set_listing
      @listing = current_user.listings.friendly.find(params[:id])
    end

    # Status changes are driven by the dedicated POST resources
    # (submissions / archival / sale_mark); the button label doubles as the
    # intent marker on the form itself.
    def submitting?
      params[:intent] == "submit"
    end

    def form_params
      params.require(:listing).permit(
        :title, :description, :condition, :quantity, :price, :original_price,
        :shipping_price, :shipping_available, :free_shipping, :local_pickup,
        :allow_offers, :city, :region, :postal_code, :category_root, :category_child,
        specs: {}, photos: [], remove_photo_ids: [], seller_tag_ids: []
      ).to_h
    end

    # Tabs + counts for the index template (also rendered by destroy's 422).
    def assign_index_data
      @tabs = TABS
      listings = current_user.listings
      @counts = Listing.status_counts(listings)
      scope = @tab == "all" ? listings : listings.where(status: @tab)
      @pagy, @listings = pagy(scope.order(updated_at: :desc, id: :desc).with_card_data,
                              limit: PER_PAGE)
    end

    # Form state for the category picker: submitted slugs win; otherwise the
    # listing's own category chain (walking up to the root). @picker_category
    # is the deepest selected category whose spec fields we pre-render.
    def assign_category_state(raw = nil)
      @category_root = raw && raw[:category_root].presence
      @category_child = raw && raw[:category_child].presence

      if @category_root.nil? && @listing.category
        chain = []
        node = @listing.category
        while node
          chain.unshift(node)
          node = node.parent
        end
        @category_root = chain.first.slug
        @category_child ||= @listing.category.slug if @listing.category.parent_id
      end

      slug = @category_child.presence || @category_root
      @picker_category = slug && Category.friendly.find(slug)
    rescue ActiveRecord::RecordNotFound
      @picker_category = nil
    end
  end
end
