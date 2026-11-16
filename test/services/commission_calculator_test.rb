require "test_helper"

class CommissionCalculatorTest < ActiveSupport::TestCase
  test "returns zero when the commissions flag is off" do
    Flipper.disable(:commissions)
    Setting.set("commission_percent", "5")
    assert_equal 0, CommissionCalculator.new(total_cents: 100_000).call
  end

  test "applies the commission_percent setting when the flag is on" do
    Flipper.enable(:commissions)
    Setting.set("commission_percent", "5")
    assert_equal 5_000, CommissionCalculator.new(total_cents: 100_000).call
  ensure
    Flipper.disable(:commissions)
  end

  test "rounds to whole cents" do
    Flipper.enable(:commissions)
    Setting.set("commission_percent", "2.5")
    assert_equal 250, CommissionCalculator.new(total_cents: 10_000).call
  ensure
    Flipper.disable(:commissions)
  end
end
