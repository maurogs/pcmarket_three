class StoresController < ApplicationController
  TABS = %w[listings about reviews].freeze
  REVIEWS_PER_PAGE = 10

  allow_unauthenticated_access

  # Public seller storefront: /stores/:id with Listings / About / Reviews tabs.
  def show
    @store = Store.friendly.find(params[:id])
    @tab = params[:tab].presence_in(TABS) || "listings"

    if @tab == "reviews"
      @reviews_pagy, @reviews = pagy(@store.reviews.recent_first.includes(:reviewer),
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
