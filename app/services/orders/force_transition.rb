module Orders
  # Admin "force status" write path (Phase 6b): the reason is required and
  # rides along in the notification payload; the audit row is written by the
  # controller. Both parties get a Notification and an e-mail.
  class ForceTransition
    Result = Struct.new(:order, :error, keyword_init: true)

    def self.call(order:, to:, reason:)
      new(order: order, to: to, reason: reason).call
    end

    def initialize(order:, to:, reason:)
      @order = order
      @to = to.to_s
      @reason = reason.to_s.strip
    end

    def call
      return Result.new(error: :reason_missing) if @reason.blank?
      return Result.new(error: :invalid_status) unless Order.statuses.key?(@to)

      from = @order.status

      ActiveRecord::Base.transaction do
        @order.force_status!(@to)
        notify
      end

      Result.new(order: @order)
    rescue Order::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :order, :to

    def notify
      [ order.buyer, order.seller ].each do |recipient|
        Notification.create!(user: recipient, kind: "order_updated",
                             payload: { "order_id" => order.id, "status" => to })
        OrderMailer.with(order: order, recipient: recipient).status_changed.deliver_later
      end
    end
  end
end
