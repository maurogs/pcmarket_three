class Label < ApplicationRecord
  include TranslatableJsonb
  include LocalizedSlug

  has_many :listing_labels, dependent: :destroy
  has_many :listings, through: :listing_labels

  validates :slug, presence: true, uniqueness: true
  validates :names, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_nil: true

  def name
    names[I18n.locale.to_s].presence || names["en"].presence
  end
end
