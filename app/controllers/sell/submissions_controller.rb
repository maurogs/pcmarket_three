module Sell
  # POST /sell/listings/:listing_id/submission — moves the seller's own
  # listing to pending_review and notifies admins (Listings::Submit).
  class SubmissionsController < BaseController
    def create
      listing = current_user.listings.friendly.find(params[:listing_id])
      Listings::Submit.new(listing).call
      redirect_to sell_listings_path(tab: "pending_review"), notice: t(".submitted")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to edit_sell_listing_path(listing), alert: t(".invalid", errors: e.record.errors.full_messages.to_sentence)
    rescue Listing::InvalidTransition => e
      redirect_to sell_listings_path, alert: e.message
    end
  end
end
