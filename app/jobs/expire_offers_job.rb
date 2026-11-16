# Housekeeping for offers (recurring, every 15 minutes — config/recurring.yml):
# pending offers past their expires_at flip to `expired`, and reservations
# past reserved_until go back to the public pool (`approved`). Both updates
# are single statements guarded by the current status, so they are safe to
# run concurrently and idempotent.
class ExpireOffersJob < ApplicationJob
  def perform
    now = Time.current

    Offer.where(status: :pending)
         .where("expires_at IS NOT NULL AND expires_at <= ?", now)
         .update_all(status: Offer.statuses[:expired], updated_at: now)

    Listing.where(status: :reserved)
           .where("reserved_until IS NOT NULL AND reserved_until <= ?", now)
           .update_all(status: Listing.statuses[:approved],
                       reserved_for_id: nil, reserved_until: nil, updated_at: now)
  end
end
