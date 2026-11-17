module Carts
  # Login merge: fold the guest cookie cart into the user's cart. Same
  # listing in both carts → quantities stack, capped at the listing's
  # stock; listings that are no longer purchasable for this buyer are
  # dropped instead of carried over. The guest cart is destroyed either
  # way. Idempotent: a missing/empty/identical cart is a no-op.
  class Merge
    Result = Struct.new(:merged_count, :discarded_count, keyword_init: true)

    def self.call(from:, to:)
      new(from: from, to: to).call
    end

    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def call
      return Result.new(merged_count: 0, discarded_count: 0) if from.nil? || from == to

      merged = 0
      discarded = 0

      ActiveRecord::Base.transaction do
        from.cart_items.includes(:listing).find_each do |item|
          listing = item.listing

          if listing.nil? || !listing.purchasable_by?(to.user)
            discarded += 1
          else
            target = to.cart_items.find_or_initialize_by(listing_id: listing.id)
            desired = (target.persisted? ? target.quantity : 0) + item.quantity
            target.quantity = [ desired, listing.quantity ].min
            merged += 1 if target.save
          end

          item.destroy
        end
        from.destroy
      end

      Result.new(merged_count: merged, discarded_count: discarded)
    end

    private

    attr_reader :from, :to
  end
end
