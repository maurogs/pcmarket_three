module Api
  module V1
    # Browse/search over public listings — GET /api/v1/listings and the
    # store-scoped GET /api/v1/stores/:store_id/listings (same controller,
    # Rails injects store_id). All the search machinery (full text, facets,
    # sort, pagination) lives in ListingSearch, shared with the web.
    #
    # GET /api/v1/listings/:id shows only what the public can see: approved,
    # sold and reserved listings; drafts 404 (owners/admins with a valid
    # token additionally see their own private ones, same as the web).
    class ListingsController < BaseController
      skip_before_action :authenticate_token!
      before_action :authenticate_token_if_present

      MAX_LIMIT = 100

      def index
        if params[:store_id].present?
          store = Store.visible.friendly.find(params[:store_id])
          @search_params = search_params.merge(seller: store.slug)
        else
          @search_params = search_params
        end

        @result = ListingSearch.new(@search_params, country_code: api_country_code,
                                    request: request, limit: limit).call
        set_link_header @result.pagy

        # Public catalogue: identical body for every caller (cards carry no
        # personalisation), so anyone's If-None-Match can hit 304. Strong
        # validators on purpose: Rack only ever echoes a strong ETag back to the
        # client, so a weak one could never match the If-None-Match it returns.
        fresh_when strong_etag: [ I18n.locale, api_country_code, request.fullpath,
                                  @result.pagy.count,
                                  @result.records.maximum(:updated_at) ]
      end

      def show
        listing = Listing.friendly.find(params[:id])
        unless listing.approved? || listing.sold? || listing.reserved? || owner_or_admin?(listing)
          raise ActiveRecord::RecordNotFound
        end

        @listing = listing
        fresh_when strong_etag: [ I18n.locale, listing.cache_key_with_version ]

        ListingViewJob.perform_later(listing.id) unless owner_or_admin?(listing)
      end

      private

      # Same whitelist the web applies (ApplicationController#search_params).
      def search_params
        params.slice(:q, :category, :min_price, :max_price, :condition, :f,
                     :labels, :tags, :seller, :sort, :page)
      end

      def limit
        requested = params[:limit].to_i
        requested.between?(1, MAX_LIMIT) ? requested : ListingSearch::PER_PAGE
      end

      def owner_or_admin?(listing)
        user = Current.user
        return false if user.nil?

        user.admin? || listing.user_id == user.id
      end
    end
  end
end
