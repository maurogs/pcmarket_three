class ModerationEvent < ApplicationRecord
  enum :action, { approved: 0, rejected: 1, edited: 2, unpublished: 3 }

  belongs_to :listing
  belongs_to :admin, class_name: "User"

  validates :action, presence: true
end
