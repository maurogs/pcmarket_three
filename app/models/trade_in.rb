# Trade-in ("Sell to us") quote → payout lifecycle. A visitor asks for a
# quote (TradeIns::Quote writes this row with status `quoted`, user_id nil,
# expires_at +7 days); accepting requires login and stamps the user. From
# there admins walk the shipment: received → inspected → paid (or rejected /
# expired) via #transition_to! (audited in Admin::TradeInsController).
class TradeIn < ApplicationRecord
  class InvalidTransition < StandardError; end

  # Quote validity window (7 days, per the marketing copy).
  QUOTE_TTL = 7.days

  enum :component_type, { gpu: 0, cpu: 1 }
  enum :condition, { like_new: 0, good: 1, fair: 2, for_parts: 3 }
  enum :status, {
    quoted: 0, accepted: 1, received: 2, inspected: 3, paid: 4, rejected: 5, expired: 6
  }

  belongs_to :user, optional: true

  validates :component_type, presence: true
  validates :model, presence: true, length: { maximum: 120 }
  validates :condition, presence: true
  validates :offered_cents, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :expires_at, presence: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  # Admin-side state machine. `accept!` is the buyer step (login required);
  # the rest are fulfilment steps admins perform from the admin panel.
  TRANSITIONS = {
    "quoted" => %w[accepted rejected expired],
    "accepted" => %w[received rejected],
    "received" => %w[inspected rejected],
    "inspected" => %w[paid rejected]
  }.freeze

  def transition_to!(new_status)
    allowed = TRANSITIONS.fetch(status, [])
    unless allowed.include?(new_status.to_s)
      raise InvalidTransition,
            I18n.t("trade_ins.transition.invalid",
                   from: self.class.human_attribute_name("status/#{status}"),
                   to: self.class.human_attribute_name("status/#{new_status}"))
    end

    update!(status: new_status)
  end

  # A quote past its expiry is still `quoted` in the DB until someone touches
  # it (accept attempt or the admin list). `expired?` itself comes from the
  # status enum; this checks the wall clock while the row is still open.
  def stale_quote?
    quoted? && expires_at <= Time.current
  end

  def expire!
    raise InvalidTransition, I18n.t("trade_ins.transition.invalid",
                                    from: self.class.human_attribute_name("status/#{status}"),
                                    to: self.class.human_attribute_name("status/expired")) unless quoted?

    update!(status: :expired)
  end

  # Money-like decimal value built from the integer cents column.
  def offer
    Money.new(offered_cents, "EUR")
  end
end
