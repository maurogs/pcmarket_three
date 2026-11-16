module Sell
  # POST /sell/listings/:listing_id/archival — approved/rejected/draft →
  # archived (Listing#archive!).
  class ArchivalsController < BaseController
    def create
      listing = current_user.listings.friendly.find(params[:listing_id])
      listing.archive!
      redirect_to sell_listings_path(tab: "archived"), notice: t(".archived")
    rescue Listing::InvalidTransition => e
      redirect_to sell_listings_path, alert: e.message
    end
  end
end
