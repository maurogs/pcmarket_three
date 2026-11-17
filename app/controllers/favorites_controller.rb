# Favourites / wishlist. create/destroy come from the heart button on
# listing cards and the listing page (Turbo Stream swaps the button in
# place); index is the wishlist itself. Anonymous users get bounced to
# sign-in by require_authentication, with a return_to so they land back
# after logging in.
class FavoritesController < ApplicationController
  before_action :require_authentication
  before_action :set_listing, only: :create
  before_action :set_favorite, only: :destroy

  def index
    @favorites = current_user.favorites.with_listing_data.order(created_at: :desc)
  end

  def create
    @favorite = current_user.favorites.find_or_initialize_by(listing: @listing)
    if @favorite.new_record?
      @favorite.price_cents_at_save = @listing.price_cents
      @favorite.save!
    end
    forget_favorite(@listing.id)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: favorite_streams(@listing) }
      format.html { redirect_to listing_path(@listing), status: :see_other }
    end
  end

  def destroy
    @favorite.destroy!
    forget_favorite(@listing.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("favorite_#{@listing.id}"),
          turbo_stream.replace("favorite_button_#{@listing.id}",
                               partial: "shared/favorite_button",
                               locals: { listing: @listing })
        ]
      end
      format.html { redirect_to favorites_path, status: :see_other }
    end
  end

  private

  def set_listing
    @listing = Listing.visible.find(params[:listing_id])
  end

  def set_favorite
    @favorite = current_user.favorites.find(params[:id])
    @listing = @favorite.listing
  end

  def favorite_streams(listing)
    [
      turbo_stream.replace("favorite_button_#{listing.id}",
                           partial: "shared/favorite_button",
                           locals: { listing: listing })
    ]
  end
end
