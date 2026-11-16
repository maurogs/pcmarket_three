# Money-like value object assembled from integer cents columns
# (avoids pulling in the monetize gem while keeping amounts typed).
class Money
  attr_reader :cents, :currency

  def initialize(cents, currency = "EUR")
    @cents = Integer(cents)
    @currency = currency
  end

  def amount
    BigDecimal(cents) / 100
  end
  alias to_d amount

  def to_s
    format("%.2f %s", amount, currency)
  end
end
