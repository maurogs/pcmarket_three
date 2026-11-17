module Api
  module V1
    # GET /api/v1/favorites — the wishlist with the price-drop badge the web
    # shows; POST /api/v1/favorites hearts a listing (idempotent); DELETE
    # /api/v1/favorites/:id removes a favorite RECORD (its id comes from the
    # index), mirroring FavoritesController#destroy.
    class FavoritesController < BaseController
      PER_PAGE = 24

      def index
        @pagy, @favorites = pagy(
          Current.user.favorites.with_listing_data.order(created_at: :desc),
          limit: PER_PAGE
        )
        set_link_header @pagy
      end

      def create
        listing = Listing.visible.friendly.find(params[:listing_id])
        favorite = Current.user.favorites.find_or_initialize_by(listing: listing)
        if favorite.new_record?
          favorite.price_cents_at_save = listing.price_cents
          favorite.save!
        end

        render json: { message: t("api.favorites.added"), favorited: true, favorite_id: favorite.id }
      end

      def destroy
        favorite = Current.user.favorites.find(params[:id])
        favorite.destroy!
        render json: { message: t("api.favorites.removed") }
      end
    end
  end
end
