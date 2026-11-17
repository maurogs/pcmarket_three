module Api
  module V1
    # Public store directory: GET /api/v1/stores (visible stores, name
    # search, ordered by activity), GET /api/v1/stores/:id (slug or id via
    # FriendlyId), store review pages, and follow/unfollow for token holders.
    # Hidden (GDPR-anonymized) stores 404 — same Store.visible rule as web.
    class StoresController < BaseController
      skip_before_action :authenticate_token!
      before_action :authenticate_token_if_present

      PER_PAGE = 24

      def index
        scope = Store.visible.order(listings_count: :desc, sales_count: :desc, id: :desc)
        scope = scope.where("stores.name ILIKE ?", "%#{Store.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
        @pagy, @stores = pagy(scope, limit: PER_PAGE)
        set_link_header @pagy
      end

      def show
        @store = Store.visible.friendly.find(params[:id])
        fresh_when strong_etag: [ I18n.locale, @store.cache_key_with_version ]
      end
    end
  end
end
