class SpecOption < ApplicationRecord
  include TranslatableJsonb

  belongs_to :spec_attribute

  validates :value, presence: true, uniqueness: { scope: :spec_attribute_id },
            format: { with: /\A[a-z0-9][a-z0-9_\-]*\z/ }
  validates :names, presence: true
  validates :position, numericality: { only_integer: true }

  scope :popular, -> { where(popular: true) }
  # Popular options render first; the rest sit behind a "show more" toggle.
  scope :ordered, -> { order(popular: :desc, position: :asc, id: :asc) }

  def name
    names[I18n.locale.to_s].presence || names["en"].presence
  end

  # Listings currently carrying this value in their specs jsonb — the count
  # that blocks a plain delete (use SpecOptions::Merge instead).
  def listings_using_count
    Listing.using_spec_value(spec_attribute.key, value).count
  end
end
