module Moderations
  # Checkbox approve/reject over a page of queue rows. Each listing runs
  # through the same Approve/Reject services as the single-record flow, and
  # listings whose state moved since the page was rendered are counted as
  # skipped (their InvalidTransition is swallowed, never rolled back onto
  # the batch).
  class Bulk
    DECISIONS = %w[approve reject].freeze

    Result = Struct.new(:decision, :done, :skipped, keyword_init: true) do
      def any?
        done.positive?
      end
    end

    def self.call(listing_ids:, decision:, reason_key: nil, note: nil, admin:)
      new(listing_ids, decision, reason_key, note, admin).call
    end

    def initialize(listing_ids, decision, reason_key, note, admin)
      @listing_ids = Array(listing_ids).first(50)
      @decision = decision.to_s
      @reason_key = reason_key
      @note = note
      @admin = admin
    end

    def call
      raise ArgumentError, "unknown decision #{decision.inspect}" unless DECISIONS.include?(decision)

      done = 0
      skipped = 0
      Listing.where(id: listing_ids).find_each do |listing|
        if decision == "approve"
          Moderations::Approve.call(listing, admin: admin)
        else
          Moderations::Reject.call(listing, reason_key: reason_key, note: note, admin: admin)
        end
        done += 1
      rescue Listing::InvalidTransition, Moderations::Reject::InvalidReason
        skipped += 1
      end
      Result.new(decision: decision, done: done, skipped: skipped)
    end

    private

    attr_reader :listing_ids, :decision, :reason_key, :note, :admin
  end
end
