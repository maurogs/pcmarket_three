module Moderations
  # Rejecting a pending listing. `reason_key` is one of the predefined
  # REASONS (labels live under admin.rejections.reasons.*); the stored
  # reason_text is the translated label plus the optional moderator note,
  # which is what the seller sees on their "Needs attention" list.
  class Reject
    REASONS = %w[
      blurry_photos missing_info prohibited_item price_misleading
      duplicate wrong_category other
    ].freeze

    class InvalidReason < StandardError; end

    def self.call(listing, reason_key:, note:, admin:)
      new(listing, reason_key, note, admin).call
    end

    def initialize(listing, reason_key, note, admin)
      @listing = listing
      @reason_key = reason_key.to_s
      @note = note.to_s.strip.presence
      @admin = admin
    end

    def call
      raise InvalidReason unless REASONS.include?(reason_key)

      reason_text = [ t_reason, note ].compact.join(" — ")
      listing.reject!(reason_text, admin: admin)
      notify_seller
      listing
    end

    private

    attr_reader :listing, :reason_key, :note, :admin

    def t_reason
      I18n.t("admin.rejections.reasons.#{reason_key}")
    end

    def notify_seller
      Notification.create!(
        user: listing.user, kind: "listing_rejected",
        payload: { "listing_id" => listing.id, "title" => listing.title,
                   "reason" => reason_key, "note" => note }
      )
      ModerationMailer.rejected(listing: listing, recipient: listing.user).deliver_later
    end
  end
end
