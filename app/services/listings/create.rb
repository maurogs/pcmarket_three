# Creates a listing from raw sell-form params. Owns the cross-cutting rules:
# the seller's store is auto-created (Stores::EnsureFor), category slugs are
# resolved, specs/prices normalised, and — when the seller clicked "Submit
# for review" — the new listing goes straight to pending_review and admins
# are notified inside the same transaction.
module Listings
  class Create
    Result = Struct.new(:listing, :submitted, keyword_init: true) do
      def saved?
        listing.persisted?
      end

      def submitted?
        !!submitted
      end
    end

    def initialize(user, raw)
      @user = user
      @raw = raw
    end

    def call(submit: false)
      category, category_error = FormAttributes.resolve_category(@raw[:category_root], @raw[:category_child])
      attrs, invalid_prices = FormAttributes.build(@raw, category: category)
      attrs[:category] = category if category

      listing = @user.listings.new(
        attrs.merge(
          country_code: @user.country_code.presence || "ES"
        )
      )
      listing.seller_tag_ids = FormAttributes.seller_tag_ids(@raw)
      photos = FormAttributes.uploaded_photos(@raw)
      listing.photos.attach(photos) if photos.any?

      apply_form_errors(listing, category_error:, invalid_prices:)
      return Result.new(listing: listing, submitted: false) if listing.errors.any?

      begin
        Listing.transaction do
          store = Stores::EnsureFor.new(@user).call
          listing.store = store
          listing.allow_offers = FormAttributes.allow_offers_value(@raw, store)
          listing.save!
          Listings::Submit.new(listing).call if submit
        end
      rescue ActiveRecord::RecordInvalid
        # Rollback keeps "submit" atomic: nothing is stored when the
        # :submission-context validations fail, and the form re-renders
        # with those errors.
        return Result.new(listing: listing, submitted: false)
      end

      Result.new(listing: listing, submitted: submit)
    end

    private

    def apply_form_errors(listing, category_error:, invalid_prices:)
      case category_error
      when :not_found then listing.errors.add(:category_id, :not_found)
      when :blank then listing.errors.add(:category_id, :blank)
      end
      invalid_prices.each { |attribute| listing.errors.add(attribute, :not_a_number) }
    end
  end
end
