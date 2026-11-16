# Platform commission for an order. Reads the commission_percent Setting and
# only applies it while the Flipper :commissions flag is enabled.
class CommissionCalculator
  attr_reader :total_cents

  def initialize(total_cents:)
    @total_cents = Integer(total_cents)
  end

  def call
    return 0 unless Flipper.enabled?(:commissions)

    percent = Setting.get("commission_percent", 0).to_d
    return 0 if percent <= 0

    (total_cents * percent / 100).round
  end
end
