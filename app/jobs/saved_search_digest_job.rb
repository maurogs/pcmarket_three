# Hourly e-mail digest: one email per user covering the saved-search
# matches their instant alerts skipped (search has email_alerts off, or
# the user had the channel paused when the match landed). Runs from
# config/recurring.yml.
class SavedSearchDigestJob < ApplicationJob
  queue_as :default

  def perform
    SavedSearchDigest.new.run
  end
end
