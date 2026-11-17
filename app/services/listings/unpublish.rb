module Listings
  # Pull a live listing out of the public catalogue (admin "unpublish").
  # Recorded as its own ModerationEvent action so the queue history reads
  # "unpublished", not "rejected".
  class Unpublish
    def self.call(listing, admin:)
      listing.archive!
      listing.moderation_events.create!(admin: admin, action: :unpublished)
      listing
    end
  end
end
