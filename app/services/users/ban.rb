module Users
  # Admin ban: stamps banned_at/ban_reason, kicks every live session and
  # API token out, and archives the seller's live listings so the catalogue
  # stays clean. Unban restores nothing automatically — the user management
  # page lists the archived ones for manual reinstatement.
  class Ban
    def self.call(user, reason:)
      new(user, reason).call
    end

    def initialize(user, reason)
      @user = user
      @reason = reason.to_s.strip.presence
    end

    def call
      ActiveRecord::Base.transaction do
        user.ban!(reason)
        user.sessions.destroy_all
        user.api_tokens.destroy_all
        archive_listings
      end
      user
    end

    private

    attr_reader :user, :reason

    # Only publicly visible listings need pulling down; archive! raises
    # InvalidTransition elsewhere, so the relation picks the safe sources.
    def archive_listings
      user.listings.where(status: [ :approved ]).find_each do |listing|
        listing.archive!
      rescue Listing::InvalidTransition
        nil
      end
    end
  end
end
