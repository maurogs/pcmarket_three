module Disputes
  # Admin dispute resolution (Phase 6b). Only disputed orders are resolved;
  # the three outcomes mirror what the platform operator can decide:
  #
  #   refund  — buyer gets their money back (full by default, or a partial
  #             amount <= total; Stripe orders are refunded via
  #             Payments::StripeRefund, direct payments are marked refunded
  #             manually by the operator).
  #   release — seller keeps the money, the order is completed.
  #
  # Both parties get a Notification + e-mail; the audit row is written by
  # the controller.
  class Resolve
    Result = Struct.new(:order, :error, keyword_init: true)

    ACTIONS = %w[refund release].freeze

    def self.call(order:, action:, amount_cents: nil)
      new(order: order, action: action, amount_cents: amount_cents).call
    end

    def initialize(order:, action:, amount_cents: nil)
      @order = order
      @action = action.to_s
      @amount_cents = amount_cents
    end

    def call
      return Result.new(error: :invalid_action) unless ACTIONS.include?(action)
      return Result.new(error: :not_disputed) unless order.disputed?

      amount = nil
      if action == "refund" && amount_cents.present?
        amount = begin
          Integer(amount_cents)
        rescue ArgumentError, TypeError
          return Result.new(error: :invalid_amount)
        end
        return Result.new(error: :amount_above_total) if amount <= 0 || amount > order.total_cents
      end

      ActiveRecord::Base.transaction do
        if action == "refund"
          refund_via_stripe!(amount)
          order.refund!(amount)
        else
          order.release_to_seller!
        end
        notify
      end

      Result.new(order: order)
    rescue Order::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :order, :action, :amount_cents

    # Stripe-processed payments are actually refunded; direct bank payments
    # are refunded outside the platform and only marked on the order.
    def refund_via_stripe!(amount)
      return if order.payment_reference.blank?

      Payments::StripeRefund.call(order: order, amount_cents: amount)
    end

    def notify
      kind = action == "refund" ? "order_refunded" : "order_resolved"
      [ order.buyer, order.seller ].each do |recipient|
        Notification.create!(user: recipient, kind: kind,
                             payload: { "order_id" => order.id })
        mailer_action = action == "refund" ? :refund_issued : :dispute_resolved
        OrderMailer.with(order: order, recipient: recipient).public_send(mailer_action).deliver_later
      end
    end
  end
end
