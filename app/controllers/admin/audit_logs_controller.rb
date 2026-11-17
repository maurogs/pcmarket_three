module Admin
  # Audit log browse page — rows are written by Admin::Auditable since
  # Phase 6a; this is the read side (filter by admin, action, subject type
  # and date range). Read-only by design.
  class AuditLogsController < BaseController
    SUBJECT_TYPES = %w[
      Listing User Store Order OrderNote Review Category SpecAttribute
      SpecOption CategorySpecAttribute Label SellerTag Country LegalPage
      NewsletterSubscription ModerationEvent
    ].freeze

    def index
      scope = AdminAuditLog.includes(:admin).recent
      scope = scope.for_admin(params[:admin_id]) if params[:admin_id].present?
      # NOTE: `action` is reserved in params, the filter is `event_action`.
      scope = scope.with_action(params[:event_action]) if params[:event_action].presence_in(AdminAuditLog.action_options)
      scope = scope.with_subject_type(params[:subject_type]) if params[:subject_type].presence_in(SUBJECT_TYPES)
      scope = scope.between_dates(parse_date(params[:from]), parse_date(params[:to]))
      @pagy, @logs = pagy(scope, limit: 50)

      @admins = User.admin.order(:username)
      @actions = AdminAuditLog.action_options
    end

    private

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
