module Admin
  # Listing-report inbox (Phase 7b): open reports first, newest last.
  # Closing is done through the nested resolution/dismissal resources;
  # both audits are written there.
  class ReportsController < BaseController
    def index
      scope = Report.includes(:listing, :user, :resolved_by)
      case params[:state]
      when "open" then scope = scope.open
      when "closed" then scope = scope.where.not(resolved_at: nil)
      end
      scope = scope.where(reason: params[:reason]) if params[:reason].presence_in(Report.reason_options)
      # Open reports first (NULL resolved_at sorts first on DESC), newest
      # within each group.
      @pagy, @reports = pagy(scope.order(resolved_at: :desc, created_at: :desc), limit: 25)
      @open_count = Report.open.count
    end

    def show
      @report = Report.includes(:listing, :user, :resolved_by).find(params[:id])
      @sibling_reports = @report.listing.reports.recent.except(:includes)
    end
  end
end
