class Notification < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true, length: { maximum: 50 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def read?
    !read_at.nil?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end
