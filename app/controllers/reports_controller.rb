# "Report this listing" (Phase 7b). Nested under listings, signed-in users
# only. One OPEN report per user per listing is enforced in the model; the
# third open report on a live listing bounces it back to moderation
# (see Report#revalidate_flooded_listing).
class ReportsController < ApplicationController
  before_action :set_listing

  def new
    @report = Report.new(listing: @listing)
  end

  def create
    # Enum assignment with a junk value would raise; treat it as "invalid"
    # instead (the select only offers valid reasons, but POSTs lie).
    unless params.dig(:report, :reason).in?(Report.reason_options)
      flash.now[:alert] = t(".invalid")
      @report = Report.new(listing: @listing)
      return render :new, status: :unprocessable_entity
    end

    @report = Report.new(report_params)
    @report.listing = @listing
    @report.user = current_user

    if @report.save
      redirect_to listing_path(@listing), notice: t(".created")
    else
      flash.now[:alert] = t(".invalid")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_listing
    @listing = Listing.friendly.find(params[:listing_id])
    # Same visibility rules as the public listing page.
    raise ActiveRecord::RecordNotFound unless @listing.approved? || @listing.sold? || @listing.reserved?
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def report_params
    params.require(:report).permit(:reason, :details)
  end
end
