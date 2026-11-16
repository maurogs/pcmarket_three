# Money-like value object assembled from integer cents columns
# (avoids pulling in the monetize gem while keeping amounts typed).
class Money
  # Currency symbols rendered by `formatted` and ListingsHelper#money.
  UNITS = { "EUR" => "€", "GBP" => "£", "USD" => "$" }.freeze

  # Pure formatting helper — number_to_currency needs no view context.
  include ActionView::Helpers::NumberHelper

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

  # Locale-formatted currency string, usable from models and services
  # (persisted system-message bodies, mailer copy).
  def formatted
    number_to_currency(amount, unit: UNITS.fetch(currency, currency), precision: 2)
  end
end
