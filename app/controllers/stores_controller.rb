class StoresController < ApplicationController
  TABS = %w[listings about reviews].freeze
  REVIEWS_PER_PAGE = 10

  allow_unauthenticated_access

  # Public seller storefront: /stores/:id with Listings / About / Reviews tabs.
  def show
    @store = Store.friendly.find(params[:id])

    # GDPR-anonymized stores (hidden) disappear from the public catalogue;
    # the owner and admins can still open the page.
    if @store.hidden? && current_user != @store.user && !current_user&.admin?
      raise ActiveRecord::RecordNotFound
    end

    # Renamed stores: FriendlyId :history resolves the old slug, then we 301
    # to the canonical URL so backlinks and SEO value survive the rename.
    if @store.slug != params[:id]
      redirect_to store_path(@store, tab: params[:tab].presence_in(TABS)),
                  status: :moved_permanently and return
    end

    @tab = params[:tab].presence_in(TABS) || "listings"

    if @tab == "reviews"
      @reviews_pagy, @reviews = pagy(@store.reviews.visible.recent_first.includes(:reviewer),
                             limit: REVIEWS_PER_PAGE)
    else
      # The browse sidebar + results frame read @result (shared with listings
      # and category pages); the seller filter is applied inside the service.
      @result = ListingSearch.new(store_search_params,
                                  country_code: current_country_code,
                                  request: request).call
    end

    # Same cache rule as ListingsController#show: the storefront only ever lists
    # approved listings, but a signed-in visitor gets their own header, so only
    # anonymous responses may be stored by shared caches (CDN, proxies).
    shared_cacheable = Current.user.nil?
    fresh_when(etag: store_etag, last_modified: @store.updated_at,
               public: shared_cacheable,
               cache_control: { max_age: 0, must_revalidate: true, private: !shared_cacheable })
  end

  private

  # Search scoped to this seller; the category filter still applies.
  def store_search_params
    search_params.merge(seller: @store.slug)
  end

  def store_etag
    [
      I18n.locale, @tab, @store.cache_key_with_version,
      @store.listings_count, @store.reviews_count, params[:page], params[:tab]
    ]
  end
end
