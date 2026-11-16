class Address < ApplicationRecord
  belongs_to :user

  validates :full_name, presence: true, length: { maximum: 100 }
  validates :line1, presence: true, length: { maximum: 200 }
  validates :line2, length: { maximum: 200 }, allow_nil: true
  validates :city, presence: true, length: { maximum: 100 }
  validates :region, length: { maximum: 100 }, allow_nil: true
  validates :postal_code, presence: true, length: { maximum: 12 }
  validates :country_code, presence: true, length: { is: 2 }
  validates :phone, length: { maximum: 20 }, allow_nil: true

  scope :defaults, -> { where(default: true) }

  # Snapshot used as the Order#shipping_address jsonb value.
  def to_snapshot
    {
      "full_name" => full_name, "line1" => line1, "line2" => line2,
      "city" => city, "region" => region, "postal_code" => postal_code,
      "country_code" => country_code, "phone" => phone
    }
  end
end
