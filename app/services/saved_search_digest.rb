# Groups the unsent saved_search_match notifications by user and sends
# one digest per user, stamping last_notified_at on every covered saved
# search. Users who opted out of saved-search email keep their matches
# pending (they surface again if they opt back in).
class SavedSearchDigest
  MAX_LISTINGS_PER_EMAIL = 10

  def run
    User.where(id: SavedSearch.select(:user_id).distinct).find_each do |user|
      send_digest_for(user)
    end
  end

  private

  def send_digest_for(user)
    return unless user.wants_email?("saved_search")

    pending = user.saved_searches.select { |s| Notification.unsent_saved_search_matches(s).exists? }
    return if pending.empty?

    listings = listings_for(pending)
    return if listings.empty?

    SavedSearchMailer.with(user: user, listings: listings).digest.deliver_later
    pending.each { |s| s.touch(:last_notified_at) }
  end

  def listings_for(searches)
    ids = searches.flat_map { |s| Notification.unsent_saved_search_matches(s).pluck(Arel.sql("payload->>'listing_id'")) }
                  .uniq.map(&:to_i)
    Listing.where(id: ids).order(created_at: :desc).limit(MAX_LISTINGS_PER_EMAIL).to_a
  end
end
