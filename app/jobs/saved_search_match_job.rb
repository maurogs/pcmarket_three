# Fired from Listing (after the listing becomes approved). The service
# writes one saved_search_match notification per matching saved search
# (the notification centre + the digest feed on those); the instant e-mail
# goes out at most once per user when one of their searches has email
# alerts on and they want that email.
class SavedSearchMatchJob < ApplicationJob
  queue_as :default

  def perform(listing_id)
    listing = Listing.find_by(id: listing_id)
    return if listing.nil? || !listing.approved?

    matched = SavedSearches::MatchNewListing.call(listing)

    matched.group_by(&:user_id).each_value do |searches|
      user = searches.first.user
      alert_searches = searches.select(&:email_alerts)
      next if alert_searches.empty? || !user.wants_email?("saved_search")

      SavedSearchMailer.with(user: user, listing: listing).match_found.deliver_later
      # Watermark: the digest only collects matches created after this, so
      # alerts already e-mailed are never re-sent.
      alert_searches.each { |s| s.touch(:last_notified_at) }
    end
  end
end
