module Admin
  # POST /admin/reports/:report_id/dismissal — close a report as DISMISSED
  # (no action on the listing; e.g. duplicate or unsubstantiated). Audited.
  class ReportDismissalsController < BaseController
    include Auditable

    def create
      @report = Report.find(params[:report_id])

      unless @report.open?
        redirect_to admin_report_path(@report), alert: t("admin.reports.show.already_closed")
        return
      end

      @report.close!(:dismissed, admin: Current.user)
      audit!("report_dismiss", @report, listing_id: @report.listing_id, reason: @report.reason)
      redirect_to admin_report_path(@report), notice: t(".dismissed")
    end
  end
end
