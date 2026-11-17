module Admin
  # Dispute queue: disputed orders first, resolved ones behind the status
  # filter (they live in the same orders index too — this is the focused
  # workspace with the resolution flow).
  class DisputesController < BaseController
    def index
      scope = OrderFilter.call(filter_params)
      scope = scope.disputed unless params[:status].presence_in(Order.statuses.keys)
      @pagy, @orders = pagy(scope.includes(:buyer, :seller), limit: 25)
    end

    def show
      @order = Order.find(params[:id])
      @events = AdminAuditLog.for_subject(@order).recent.limit(20)
    end

    private

    def filter_params
      params.slice(:status, :seller, :buyer, :provider, :from, :to, :q).permit!.to_h
    end
  end
end
