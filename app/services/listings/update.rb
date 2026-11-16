# Updates a listing from raw sell-form params. The interesting rule lives
# here: an APPROVED listing whose MATERIAL fields (title, description,
# photos, specs, category) change goes back to pending_review, while changes
# to price, shipping, quantity, location or tags keep it live.
module Listings
  class Update
    # Listing columns whose edits require re-review (photos are tracked
    # separately because ActiveStorage changes bypass `changed`).
    MATERIAL_COLUMNS = %w[title description specs category_id].freeze

    Result = Struct.new(:listing, :saved, :re_reviewed, :submitted, keyword_init: true) do
      def saved? = saved
      def re_reviewed? = re_reviewed
      def submitted? = submitted
    end

    def initialize(listing, raw)
      @listing = listing
      @raw = raw
    end

    def call(submit: false)
      category, category_error = FormAttributes.resolve_category(@raw[:category_root], @raw[:category_child])
      attrs, invalid_prices = FormAttributes.build(@raw, category: category)
      attrs[:category] = category if category
      @listing.allow_offers = FormAttributes.allow_offers_value(@raw, @listing.store) if @raw.key?(:allow_offers)

      apply_form_errors(category_error:, invalid_prices:)
      if @listing.errors.any?
        return Result.new(listing: @listing, saved: false, re_reviewed: false, submitted: false)
      end

      was_approved = @listing.approved?
      @listing.assign_attributes(attrs)
      material_changed = (@listing.changed & MATERIAL_COLUMNS).any?
      re_reviewed = false
      submitted = false

      # Removed photo attachments are purged only once the transaction has
      # committed: `purge`/`purge_later` delete the stored file immediately, so
      # purging inside the transaction would lose the photo on a rolled-back
      # save. Collect the ids instead and purge after commit.
      purge_attachment_ids = []
      committed = false

      Listing.transaction do
        @listing.seller_tag_ids = FormAttributes.seller_tag_ids(@raw) if @raw.key?(:seller_tag_ids)
        # Attachments added here roll back with the save; only removals need
        # the deferred purge above.
        photos_changed = apply_photo_changes(purge_attachment_ids)
        raise ActiveRecord::Rollback unless @listing.save

        if was_approved && (material_changed || photos_changed)
          @listing.request_revalidation!
          re_reviewed = true
        end
        if submit && !@listing.pending_review?
          # When the material edit above already pushed it to pending_review
          # there is nothing left to submit.
          Listings::Submit.new(@listing).call
          submitted = true
        end
        committed = true
      end

      unless committed
        return Result.new(listing: @listing, saved: false, re_reviewed: false, submitted: false)
      end

      purge_removed_photos(purge_attachment_ids)

      Result.new(listing: @listing, saved: true, re_reviewed: re_reviewed, submitted: submitted)
    rescue ActiveRecord::RecordInvalid
      # :submission-context validation failure while submitting: the whole
      # update rolls back and the form re-renders with the errors.
      Result.new(listing: @listing, saved: false, re_reviewed: false, submitted: false)
    rescue Listing::InvalidTransition => e
      @listing.errors.add(:status, e.message)
      Result.new(listing: @listing, saved: false, re_reviewed: false, submitted: false)
    rescue ActiveRecord::Rollback
      Result.new(listing: @listing, saved: false, re_reviewed: false, submitted: false)
    end

    private

    # Records the ids of the attachments being removed (rows stay untouched —
    # see the deferred purge in #call) and attaches any new uploads.
    def apply_photo_changes(purge_attachment_ids)
      remove_ids = Array(@raw[:remove_photo_ids]).reject(&:blank?)
      removed = 0
      if remove_ids.any?
        ids = @listing.photos.attachments.where(id: remove_ids).pluck(:id)
        purge_attachment_ids.concat(ids)
        removed = ids.size
      end

      uploaded = FormAttributes.uploaded_photos(@raw)
      @listing.photos.attach(uploaded) if uploaded.any?

      removed.positive? || uploaded.any?
    end

    # Post-commit cleanup: `purge_later` removes the attachment rows right
    # away and defers the blob/file deletion to ActiveStorage::PurgeJob.
    def purge_removed_photos(attachment_ids)
      attachment_ids.each do |id|
        ActiveStorage::Attachment.find_by(id: id)&.purge_later
      end
    end

    def apply_form_errors(category_error:, invalid_prices:)
      case category_error
      when :not_found then @listing.errors.add(:category_id, :not_found)
      when :blank then @listing.errors.add(:category_id, :blank)
      end
      invalid_prices.each { |attribute| @listing.errors.add(attribute, :not_a_number) }
    end
  end
end
