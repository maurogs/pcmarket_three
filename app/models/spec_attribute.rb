class SpecAttribute < ApplicationRecord
  # prefixed: bare values like `select`/`number` would clash with AR query methods
  enum :input_type, { select: 0, multi_select: 1, number: 2, text: 3, boolean: 4 },
       prefix: true

  has_many :category_spec_attributes, dependent: :destroy
  has_many :categories, through: :category_spec_attributes
  has_many :spec_options, -> { order(popular: :desc, position: :asc, id: :asc) },
           dependent: :destroy, inverse_of: :spec_attribute

  validates :key, presence: true, uniqueness: true,
            format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :names, presence: true
  validates :unit, length: { maximum: 30 }, allow_nil: true
  validates :group, length: { maximum: 50 }, allow_nil: true
  validates :position, numericality: { only_integer: true }

  scope :filterable, -> { where(filterable: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def name
    names[I18n.locale.to_s].presence || names["en"].presence
  end

  # Usable as a checkbox-list filter (options or true/false; free text and
  # plain numbers are excluded).
  def facet?
    filterable? && (input_type_select? || input_type_multi_select? || input_type_boolean?)
  end

  # Cast a submitted filter value to the type stored in the listing `specs`
  # jsonb so containment comparisons match (booleans are stored as JSON true/false).
  def spec_json_scalar(value)
    input_type_boolean? ? ActiveRecord::Type::Boolean.new.cast(value) : value.to_s
  end
end
