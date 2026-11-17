# Recurring order housekeeping (see config/recurring.yml):
#   * delivered orders whose buyer-protection window has lapsed are
#     completed automatically;
#   * pending_payment orders older than Order::AUTO_CANCEL_AFTER (72 h)
#     are cancelled — Order#cancel! restores the listings.
# Both run through Orders::Transition so notifications stay consistent.
class AutoCompleteOrdersJob < ApplicationJob
  def perform
    Order.awaiting_auto_completion.find_each do |order|
      Orders::Transition.call(order: order, action: "completed")
    end

    Order.auto_cancellable.find_each do |order|
      Orders::Transition.call(order: order, action: "cancelled")
    end
  end
end
