module Admin
  class DashboardsController < BaseController
    def show
      @period = params[:period].to_i.presence_in(Admin::DashboardStats::PERIODS) || 30
      @stats = Admin::DashboardStats.call(days: @period)
      @oldest_pending = Admin::DashboardStats.oldest_pending_listings
      @latest_signups = Admin::DashboardStats.latest_signups
    end
  end
end
