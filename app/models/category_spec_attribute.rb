class CategorySpecAttribute < ApplicationRecord
  belongs_to :category
  belongs_to :spec_attribute

  validates :spec_attribute_id, uniqueness: { scope: :category_id }
  validates :position, numericality: { only_integer: true }
end
