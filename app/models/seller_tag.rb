class SellerTag < ApplicationRecord
  has_many :listing_tags, dependent: :destroy
  has_many :listings, through: :listing_tags

  validates :slug, presence: true, uniqueness: true
  validates :names, presence: true

  def name
    names[I18n.locale.to_s].presence || names["en"].presence
  end
end
