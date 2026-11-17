module Users
  # GDPR erasure (right to be forgotten): wipes personal data while order
  # and review rows stay intact (their user shows as "Deleted user").
  # Refuses while the account still has orders in flight — those must be
  # settled or cancelled first.
  class Anonymize
    OpenOrderError = Class.new(StandardError)

    CLOSED_ORDER_STATUSES = %w[completed cancelled].freeze

    def self.call(user)
      new(user).call
    end

    def self.open_orders_count(user)
      Order.where(buyer_id: user.id).or(Order.where(seller_id: user.id))
          .where.not(status: CLOSED_ORDER_STATUSES).count
    end

    def initialize(user)
      @user = user
    end

    def call
      raise OpenOrderError if self.class.open_orders_count(user) > 0

      # Collected BEFORE the transaction so a rollback keeps every attachment;
      # purge_later runs after the commit (never inside the transaction —
      # see the Listings photo-purge regression in the sell tests).
      attachments = [ user.avatar, user.export ].select(&:attached?)

      ActiveRecord::Base.transaction do
        anonymize_columns
        destroy_related_records
        archive_listings
      end

      # Avatar AND the GDPR export artifact both hold personal data.
      attachments.each(&:purge_later)
      user
    end

    private

    attr_reader :user

    def anonymize_columns
      # update_columns skips validations: the anonymized identity is final.
      user.update_columns(
        email_address: "deleted-#{user.id}@invalid",
        username: "deleted-#{user.id}",
        first_name: nil,
        last_name: nil,
        phone: nil,
        updated_at: Time.current
      )
      # A random unusable password; sessions and tokens are destroyed below.
      user.update!(password: SecureRandom.base58(32))
      user.store&.update!(hidden: true)
    end

    def destroy_related_records
      user.sessions.destroy_all
      user.api_tokens.destroy_all
      user.addresses.destroy_all
      user.notifications.destroy_all
      user.favorites.destroy_all
      user.saved_searches.destroy_all
      user.following.destroy_all
      user.blocks_cast.destroy_all
      user.blocks_received.destroy_all
      Conversation.clear_unread_cache(user)
    end

    # Listings leave the catalogue (drafts included); sold ones keep their
    # order history link.
    def archive_listings
      user.listings.where.not(status: %w[archived sold]).find_each do |listing|
        begin
          listing.archive!
        rescue Listing::InvalidTransition
          nil
        end
      end
    end
  end
end
