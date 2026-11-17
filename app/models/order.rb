class Order < ApplicationRecord
  class InvalidTransition < StandardError; end

  # Buyer protection: while the window is open the buyer can still open a
  # dispute after confirming delivery. AutoCompleteOrdersJob completes
  # delivered orders once it lapses.
  BUYER_PROTECTION_WINDOW = 2.days
  # pending_payment orders older than this are auto-cancelled by
  # AutoCompleteOrdersJob (listings restored).
  AUTO_CANCEL_AFTER = 72.hours

  # Courier options for the seller shipment form (labels in the locale
  # files, tracking links built per carrier in OrdersHelper).
  CARRIERS = %w[Correos SEUR MRW GLS DHL UPS Other].freeze

  enum :status, {
    pending_payment: 0, paid: 1, shipped: 2, delivered: 3,
    completed: 4, cancelled: 5, refunded: 6, disputed: 7
  }

  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"
  has_many :order_items, dependent: :destroy
  has_many :order_notes, dependent: :destroy
  has_one :review, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :carrier, inclusion: { in: CARRIERS }, allow_nil: true
  validates :subtotal_cents, :shipping_cents, :commission_cents, :total_cents, :refund_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validate :refund_within_total

  # Disputes: open (unresolved) vs. the ones an admin has already resolved.
  scope :disputed, -> { where(status: :disputed) }

  before_validation :assign_number, on: :create
  before_validation :recalculate_total

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Delivered orders whose buyer-protection window has lapsed: the
  # auto-completion target of AutoCompleteOrdersJob.
  scope :awaiting_auto_completion, -> {
    delivered.where(buyer_protection_until: ..Time.current)
  }

  # Abandoned checkouts: still pending_payment after the payment window.
  scope :auto_cancellable, -> {
    pending_payment.where(created_at: ...AUTO_CANCEL_AFTER.ago)
  }

  # What the seller keeps: the platform commission is charged on top of the
  # total, so it is not part of the seller's revenue.
  def net_revenue_cents
    total_cents - commission_cents
  end

  # Applies the configured platform commission (0 unless the commissions
  # flag is on — see CommissionCalculator).
  def apply_commission!
    self.commission_cents = CommissionCalculator.new(total_cents: subtotal_cents).call
    recalculate_total
  end

  # --- State machine (guards raise Order::InvalidTransition) --------------

  def pay!
    ensure_transition!(from: [ :pending_payment ], to: :paid)
    update!(status: :paid, paid_at: Time.current)
  end

  def ship!(carrier:, tracking_number: nil)
    ensure_transition!(from: [ :paid ], to: :shipped)
    update!(status: :shipped, carrier: carrier, tracking_number: tracking_number,
            shipped_at: Time.current)
  end

  # Buyer confirms delivery: the protection window starts here (nil until
  # delivered — see the checkout phase notes).
  def mark_delivered!
    ensure_transition!(from: [ :shipped ], to: :delivered)
    update!(status: :delivered, delivered_at: Time.current,
            buyer_protection_until: Time.current + BUYER_PROTECTION_WINDOW)
  end

  def complete!
    ensure_transition!(from: [ :delivered ], to: :completed)
    update!(status: :completed, completed_at: Time.current)
  end

  # Buyer cancels while pending_payment, seller while not yet shipped; the
  # role split lives in the controllers, the model accepts both open
  # states. Cancelling puts every listing back on sale (see restore).
  def cancel!
    ensure_transition!(from: [ :pending_payment, :paid ], to: :cancelled)
    update!(status: :cancelled, cancelled_at: Time.current)
    restore_listings!
  end

  # Buyer opens a dispute after delivery, inside the protection window.
  def open_dispute!
    ensure_transition!(from: [ :delivered ], to: :disputed)
    raise InvalidTransition, I18n.t("orders.transition.protection_closed") unless protection_open?

    update!(status: :disputed)
  end

  # --- Dispute resolutions (admin-only, Disputes::Resolve is the caller) ---

  # Full or partial refund of a disputed order. `amount_cents` nil refunds
  # the whole total; partial refunds must not exceed it (Disputes::Resolve
  # checks first, this guard keeps the column self-consistent).
  def refund!(amount_cents = nil)
    ensure_transition!(from: [ :disputed ], to: :refunded)
    amount = amount_cents.nil? ? total_cents : Integer(amount_cents)
    update!(status: :refunded, refund_cents: amount)
  end

  # "The seller was right": close the dispute in the seller's favour.
  def release_to_seller!
    ensure_transition!(from: [ :disputed ], to: :completed)
    update!(status: :completed, completed_at: completed_at || Time.current)
  end

  # Admin override: move an order to any other status regardless of the
  # buyer/seller state machine (reason + audit are enforced upstream in
  # Orders::ForceTransition / the controller). Timestamps follow the target
  # status; cancelling a fulfilled order also restores the listings.
  def force_status!(to)
    to = to.to_s
    raise InvalidTransition, I18n.t("orders.transition.invalid", from: self.class.human_attribute_name("status/#{status}"),
                                                                  to: self.class.human_attribute_name("status/#{to}")) if !self.class.statuses.key?(to) || to == status.to_s

    attrs = { status: to }
    now = Time.current
    attrs[:paid_at] = now if to == "paid" && paid_at.nil?
    attrs[:shipped_at] = now if to == "shipped" && shipped_at.nil?
    attrs[:delivered_at] = now if to == "delivered" && delivered_at.nil?
    attrs[:completed_at] = now if to == "completed" && completed_at.nil?
    attrs[:cancelled_at] = now if to == "cancelled" && cancelled_at.nil?
    transaction { update!(attrs) }
    restore_listings! if to == "cancelled"
  end

  def protection_open?
    buyer_protection_until.nil? || buyer_protection_until > Time.current
  end

  # Timeline anchors for the order pages (nil before the step is reached).
  def step_times
    {
      placed: created_at,
      paid: paid_at,
      shipped: shipped_at,
      delivered: delivered_at,
      completed: completed_at
    }
  end

  # The thread to talk to the other party in: the conversation seeded by
  # the checkout for this order's listing, if any.
  def conversation
    Conversation.find_by(listing_id: order_items.where.not(listing_id: nil).select(:listing_id),
                         buyer_id: buyer_id, seller_id: seller_id)
  end

  private

  # Puts every still-linked listing back on sale: quantity is topped back
  # up, listings sold or reserved for this buyer by this order go live
  # again. Listings an admin sold/archived elsewhere are left alone.
  def restore_listings!
    order_items.includes(:listing).find_each do |item|
      listing = item.listing
      next if listing.nil?

      listing.add_back_quantity!(item.quantity)
      if listing.reserved_for_id == buyer_id
        listing.release_reservation!
      elsif listing.sold?
        listing.reinstate!
      end
    end
  end

  def ensure_transition!(from:, to:)
    return if from.map(&:to_s).include?(status.to_s)

    raise InvalidTransition,
          I18n.t("orders.transition.invalid", from: self.class.human_attribute_name("status/#{status}"),
                                              to: self.class.human_attribute_name("status/#{to}"))
  end

  def assign_number
    return if number.present?

    seq = self.class.connection.select_value("SELECT nextval('order_number_seq')")
    self.number = "PCM-#{Time.current.year}-#{format('%06d', seq)}"
  end

  def recalculate_total
    self.total_cents = subtotal_cents + shipping_cents + commission_cents
  end

  def refund_within_total
    return if refund_cents.nil? || total_cents.nil? || refund_cents <= total_cents

    errors.add(:refund_cents, :greater_than_total)
  end
end
