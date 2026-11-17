class Offer < ApplicationRecord
  class InvalidTransition < StandardError; end

  # A pending offer stays actionable for this long (see ExpireOffersJob,
  # which runs every 15 minutes via config/recurring.yml).
  OFFER_TTL = 48.hours

  enum :status, { pending: 0, accepted: 1, declined: 2, withdrawn: 3, expired: 4 }

  belongs_to :listing
  belongs_to :buyer, class_name: "User"

  # Convenience read-through: the seller is the listing's owner. Lets API
  # serializers (and eager loads: `includes(listing: :user)`) treat it as
  # a regular association.
  has_one :seller, through: :listing, source: :user, class_name: "User"

  # Chat bubbles generated for this offer keep a soft link to it so the
  # thread can re-render the offer card when its status changes.
  has_many :messages, dependent: :nullify

  validates :amount_cents, presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(status: :pending) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Offers placed on any of a user's listings (the "received" tab).
  scope :for_seller, ->(user) { joins(:listing).where(listings: { user_id: user.id }) }

  # The signed-in buyer's own offers (the "sent" tab).
  scope :sent_by, ->(user) { where(buyer_id: user.id) }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Pending, unexpired offers on one seller's listings (dashboard
  # "Needs attention").
  scope :pending_for_seller, ->(user) {
    for_seller(user).active.not_expired
  }

  # Time-based expiry (distinct from the `expired` status enum value).
  def time_expired?
    !expires_at.nil? && expires_at <= Time.current
  end

  def actionable?
    pending? && !time_expired?
  end

  # The thread this offer's chat card lives in, if one was started.
  def conversation
    Conversation.find_by(listing_id: listing_id, buyer_id: buyer_id)
  end

  def price
    Money.new(amount_cents, listing.currency)
  end

  # --- State machine (guards raise Offer::InvalidTransition) --------------

  # Accept is refused once the offer has time-expired even if the expiry job
  # has not flipped the status yet — otherwise a seller could reserve a
  # listing for a buyer whose offer had already lapsed.
  def accept!
    ensure_pending!
    raise InvalidTransition, "offer has expired" if time_expired?

    update!(status: :accepted)
  end

  def decline!
    ensure_pending!
    update!(status: :declined)
  end

  def withdraw!
    ensure_pending!
    update!(status: :withdrawn)
  end

  def expire!
    ensure_pending!
    update!(status: :expired)
  end

  private

  def ensure_pending!
    return if pending?

    raise InvalidTransition,
          I18n.t("offers.transition.invalid", status: self.class.human_attribute_name("status/#{status}"))
  end
end
