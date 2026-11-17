module Admin
  # POST /admin/listings/:listing_id/approval — approve a queued listing.
  # The saved-search fan-out is already an after_commit hook on the
  # ->approved transition, so nothing extra is needed here.
  class ApprovalsController < BaseController
    include Auditable

    def create
      @listing = Listing.friendly.find(params[:listing_id])
      Moderations::Approve.call(@listing, admin: Current.user)
      audit!(:approve_listing, @listing, status: @listing.status)
      redirect_to admin_moderations_path, notice: t(".approved", title: @listing.title)
    rescue Listing::InvalidTransition
      status = Listing.human_attribute_name("status/#{@listing.status}")
      redirect_to admin_moderation_path(@listing), alert: t(".already_reviewed", status: status)
    end
  end
end
