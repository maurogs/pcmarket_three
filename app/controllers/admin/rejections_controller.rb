module Admin
  # Rejection always carries a reason chosen from the predefined list
  # (Moderations::Reject::REASONS) plus an optional note — Listing#reject!
  # itself refuses blank reasons, and the form never posts one.
  class RejectionsController < BaseController
    include Auditable

    def new
      @listing = Listing.friendly.find(params[:listing_id])
    end

    def create
      @listing = Listing.friendly.find(params[:listing_id])
      reason = params[:reason].to_s

      unless Moderations::Reject::REASONS.include?(reason)
        flash.now[:alert] = t(".reason_required")
        render :new, status: :unprocessable_entity
        return
      end

      Moderations::Reject.call(@listing, reason_key: reason, note: params[:note], admin: Current.user)
      audit!(:reject_listing, @listing, reason: reason, note: params[:note].presence)
      redirect_to admin_moderations_path, notice: t(".rejected", title: @listing.title)
    rescue Listing::InvalidTransition
      status = Listing.human_attribute_name("status/#{@listing.status}")
      redirect_to admin_moderation_path(@listing), alert: t(".already_reviewed", status: status)
    end
  end
end
