class Address < ApplicationRecord
  # Spanish postal codes are five digits (the launch country); other
  # countries only need a non-blank code.
  POSTAL_CODE_FORMATS = { "ES" => /\A\d{5}\z/ }.freeze

  belongs_to :user

  validates :full_name, presence: true, length: { maximum: 100 }
  validates :line1, presence: true, length: { maximum: 200 }
  validates :line2, length: { maximum: 200 }, allow_nil: true
  validates :city, presence: true, length: { maximum: 100 }
  validates :region, length: { maximum: 100 }, allow_nil: true
  validates :postal_code, presence: true, length: { maximum: 12 }
  validates :country_code, presence: true, length: { is: 2 }
  validates :phone, length: { maximum: 20 }, allow_nil: true
  validate :postal_code_format
  validate :region_known

  before_validation :ensure_first_address_is_default, on: :create
  after_save :unset_other_defaults, if: :saved_default?

  scope :defaults, -> { where(default: true) }

  # Snapshot used as the Order#shipping_address jsonb value.
  def to_snapshot
    {
      "full_name" => full_name, "line1" => line1, "line2" => line2,
      "city" => city, "region" => region, "postal_code" => postal_code,
      "country_code" => country_code, "phone" => phone
    }
  end

  # Making one address the default clears the flag on the rest (the
  # after_save hook runs inside the same transaction).
  def mark_as_default!
    update!(default: true)
  end

  private

  def ensure_first_address_is_default
    self.default = true if user.persisted? && user.addresses.none?
  end

  def saved_default?
    default? && saved_change_to_default?
  end

  def unset_other_defaults
    user.addresses.where.not(id: id).where(default: true).update_all(default: false)
  end

  def postal_code_format
    pattern = POSTAL_CODE_FORMATS[country_code.to_s]
    return if postal_code.blank? || pattern.nil? || postal_code.match?(pattern)

    errors.add(:postal_code, :invalid_postal_code)
  end

  def region_known
    return if region.blank? || EsProvince.name?(region)

    errors.add(:region, :province_unknown)
  end
end
