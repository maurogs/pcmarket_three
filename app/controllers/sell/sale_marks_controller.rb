module Sell
  # POST /sell/listings/:listing_id/sale_mark — approved/reserved → sold
  # (Listing#mark_sold!).
  class SaleMarksController < BaseController
    def create
      listing = current_user.listings.friendly.find(params[:listing_id])
      listing.mark_sold!
      redirect_to sell_listings_path(tab: "sold"), notice: t(".sold")
    rescue Listing::InvalidTransition => e
      redirect_to sell_listings_path, alert: e.message
    end
  end
end
