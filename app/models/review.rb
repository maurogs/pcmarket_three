class Review < ApplicationRecord
  belongs_to :order
  belongs_to :reviewer, class_name: "User"
  belongs_to :store, optional: true
  belongs_to :seller, class_name: "User", optional: true

  validates :rating, presence: true,
            numericality: { only_integer: true, in: 1..5 }
  validates :order_id, uniqueness: true
  validates :body, length: { maximum: 4000 }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  # Hidden reviews (admin takedowns) are excluded from the public listing
  # and from the store rating counters.
  scope :visible, -> { where(hidden_at: nil) }
  scope :hidden, -> { where.not(hidden_at: nil) }

  after_create :refresh_store_rating
  after_destroy :refresh_store_rating
  after_update :refresh_store_rating, if: -> { saved_change_to_rating? || saved_change_to_hidden_at? }

  def hidden?
    !hidden_at.nil?
  end

  def hide!
    update!(hidden_at: Time.current)
  end

  def unhide!
    update!(hidden_at: nil)
  end

  private

  def refresh_store_rating
    target = store || seller&.store
    target&.refresh_rating!
  end
end
