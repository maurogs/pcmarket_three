# Publishes a draft/rejected/approved listing into the moderation queue
# (Listing#submit_for_review!, :submission validation context) and drops a
# "listing_submitted" notification into every admin's inbox — one batched
# INSERT, rolled back together with the status change.
module Listings
  class Submit
    def initialize(listing)
      @listing = listing
    end

    def call
      Listing.transaction do
        @listing.submit_for_review!
        notify_admins
      end
      @listing
    end

    private

    def notify_admins
      now = Time.current
      payload = { "listing_id" => @listing.id, "title" => @listing.title }
      rows = User.admin.pluck(:id).map do |user_id|
        { user_id: user_id, kind: "listing_submitted", payload: payload,
          created_at: now, updated_at: now }
      end
      Notification.insert_all(rows) if rows.any?
    end
  end
end
