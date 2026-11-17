module Admin
  # POST /admin/listings/:listing_id/unpublication — pull a live listing
  # from the catalogue (ModerationEvent action :unpublished).
  class UnpublicationsController < BaseController
    include Auditable

    def create
      @listing = Listing.friendly.find(params[:listing_id])
      Listings::Unpublish.call(@listing, admin: Current.user)
      audit!(:unpublish_listing, @listing, status: @listing.status)
      redirect_to admin_listing_path(@listing), notice: t(".unpublished")
    rescue Listing::InvalidTransition
      redirect_to admin_listing_path(@listing), alert: t(".not_unpublishable")
    end
  end
end
