class Order < ApplicationRecord
  enum :status, {
    pending_payment: 0, paid: 1, shipped: 2, delivered: 3,
    completed: 4, cancelled: 5, refunded: 6, disputed: 7
  }

  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"
  has_many :order_items, dependent: :destroy
  has_one :review, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :shipping_cents, :commission_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  before_validation :assign_number, on: :create
  before_validation :recalculate_total

  scope :recent, -> { order(created_at: :desc, id: :desc) }

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

  private

  def assign_number
    return if number.present?

    seq = self.class.connection.select_value("SELECT nextval('order_number_seq')")
    self.number = "PCM-#{Time.current.year}-#{format('%06d', seq)}"
  end

  def recalculate_total
    self.total_cents = subtotal_cents + shipping_cents + commission_cents
  end
end
