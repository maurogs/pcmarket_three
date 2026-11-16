module Sell
  # Seller landing page: KPI tiles, the 12-week sales chart, "Needs
  # attention" and top listings — every number comes from
  # Sell::DashboardStats (aggregate SQL only). The stats fragment is cached
  # five minutes per seller.
  class DashboardsController < BaseController
    def show
      @stats = Sell::DashboardStats.new(current_user).call
    end
  end
end
