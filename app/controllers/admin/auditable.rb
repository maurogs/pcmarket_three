module Admin
  # One-line audit trail for every admin write action. `details` is a small
  # jsonb summary of what was touched (never the full AR diff; the column is
  # named `details` because `changes` collides with Active Record internals).
  module Auditable
    extend ActiveSupport::Concern

    private

    def audit!(action, subject, changes = {})
      AdminAuditLog.create!(
        admin: Current.user,
        action: action.to_s,
        subject: subject,
        details: changes,
        ip: request.remote_ip
      )
    end
  end
end
