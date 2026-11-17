module Admin
  # POST /admin/reports/:report_id/resolution — close a report as RESOLVED
  # (moderation acted on the listing). Audited; closing an already-closed
  # report just bounces back with a warning.
  class ReportResolutionsController < BaseController
    include Auditable

    def create
      @report = Report.find(params[:report_id])

      unless @report.open?
        redirect_to admin_report_path(@report), alert: t("admin.reports.show.already_closed")
        return
      end

      @report.close!(:resolved, admin: Current.user)
      audit!("report_resolve", @report, listing_id: @report.listing_id, reason: @report.reason)
      redirect_to admin_report_path(@report), notice: t(".resolved")
    end
  end
end
