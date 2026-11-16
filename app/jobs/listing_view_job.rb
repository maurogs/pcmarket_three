# Bumps views_count off the request path. The controller skips enqueueing for
# the listing owner and for bot user agents.
class ListingViewJob < ApplicationJob
  queue_as :default

  def perform(listing_id)
    Listing.increment_counter(:views_count, listing_id)
  end
end
