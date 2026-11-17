module Admin
  # Checkbox approve/reject over the queue index: one aggregate audit row
  # per batch (decision + ids); each listing still gets its own
  # ModerationEvent through the shared Approve/Reject services.
  class BulkModerationsController < BaseController
    include Auditable

    def create
      ids = Array(params[:listing_ids]).map(&:to_s).first(50)
      result = Moderations::Bulk.call(
        listing_ids: ids, decision: params[:decision].to_s,
        reason_key: params[:reason], note: params[:note], admin: Current.user
      )

      audit!("bulk_#{result.decision}", nil, listing_ids: ids, done: result.done, skipped: result.skipped)

      if result.any?
        redirect_to admin_moderations_path, notice: t(".done", count: result.done, skipped: result.skipped)
      else
        redirect_to admin_moderations_path, alert: t(".none_done")
      end
    rescue ArgumentError
      redirect_to admin_moderations_path, alert: t(".invalid_decision")
    end
  end
end
