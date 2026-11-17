# Append-only trail of every admin write action (Phase 6a). Written through
# the Admin::Auditable concern; never edited or deleted from the UI.
class AdminAuditLog < ApplicationRecord
  belongs_to :admin, class_name: "User"
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :for_subject, ->(record) { where(subject: record) }

  # Browse filters (admin/audit_logs, Phase 6b).
  scope :for_admin, ->(admin_id) { where(admin_id: admin_id) }
  scope :with_action, ->(action) { where(action: action) }
  scope :with_subject_type, ->(type) { where(subject_type: type) }
  scope :between_dates, ->(from, to) {
    scope = all
    scope = scope.where(created_at: from.beginning_of_day..) if from
    scope = scope.where(created_at: ..to.end_of_day) if to
    scope
  }

  # Distinct actions already in the log, for the filter dropdown.
  def self.action_options
    distinct.order(:action).pluck(:action)
  end
end
