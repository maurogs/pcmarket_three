class SavedSearch < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :query, length: { maximum: 200 }, allow_nil: true
end
