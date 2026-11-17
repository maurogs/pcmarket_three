module Orders
  # Single write path for lifecycle transitions. The status change and its
  # guards live in the Order model; this service wraps them, maps
  # Order::InvalidTransition to a Result, and fans out the follow-ups:
  # Notification rows, e-mails (OrderMailer) and, on disputes, admin
  # notifications.
  class Transition
    Result = Struct.new(:order, :error, keyword_init: true)

    # action => Order method + recipients/kinds for notifications and the
    # e-mail each party gets (nil = no e-mail).
    ACTIONS = {
      "paid" => {
        call: ->(order) { order.pay! },
        notifications: { seller: "order_paid" },
        mail: { seller: :payment_received }
      },
      "shipped" => {
        call: ->(order, carrier:, tracking_number:) { order.ship!(carrier: carrier, tracking_number: tracking_number) },
        notifications: { buyer: "order_shipped" },
        mail: { buyer: :order_shipped }
      },
      "delivered" => {
        call: ->(order) { order.mark_delivered! },
        notifications: { buyer: "order_delivered", seller: "order_delivered" }
      },
      "completed" => {
        call: ->(order) { order.complete! },
        notifications: { buyer: "order_completed", seller: "order_completed" }
      },
      "cancelled" => {
        call: ->(order) { order.cancel! },
        notifications: { buyer: "order_cancelled", seller: "order_cancelled" }
      },
      "disputed" => {
        call: ->(order) { order.open_dispute! },
        notifications: { buyer: "order_disputed", seller: "order_disputed" }
      }
    }.freeze

    def self.call(order:, action:, **args)
      new(order: order, action: action, **args).call
    end

    def initialize(order:, action:, **args)
      @order = order
      @action = action.to_s
      @args = args
    end

    def call
      spec = ACTIONS.fetch(@action)

      ActiveRecord::Base.transaction do
        args = @args.slice(:carrier, :tracking_number)
        if args.any?
          spec[:call].call(@order, **args)
        else
          spec[:call].call(@order)
        end

        notify(spec)
      end

      Result.new(order: @order)
    rescue Order::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :order, :action

    def notify(spec)
      spec[:notifications].each do |role, kind|
        Notification.create!(user: order.public_send(role), kind: kind,
                             payload: { "order_id" => order.id })
      end

      spec[:mail]&.each do |role, mailer_action|
        recipient = order.public_send(role)
        OrderMailer.with(order: order, recipient: recipient).public_send(mailer_action).deliver_later
      end

      if action == "disputed"
        User.admin.find_each do |admin|
          Notification.create!(user: admin, kind: "order_disputed",
                               payload: { "order_id" => order.id })
        end
      end
    end
  end
end
