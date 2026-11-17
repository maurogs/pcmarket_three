# Append-only trail of every admin write action (Phase 6a). Written through
# the Admin::Auditable concern; never edited or deleted from the UI.
class AdminAuditLog < ApplicationRecord
  belongs_to :admin, class_name: "User"
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :for_subject, ->(record) { where(subject: record) }
end
