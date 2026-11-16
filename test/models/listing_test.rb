require "test_helper"

class ListingTest < ActiveSupport::TestCase
  # Fixtures load under PostgreSQL's disable_referential_integrity, which runs
  # ALTER TABLE ... DISABLE TRIGGER ALL — so the tsv trigger never sees the
  # fixture rows. Re-run the same reindex the trigger/migration use.

  def listing
    @listing ||= listings(:gigabyte)
  end

  # --- state machine ---------------------------------------------------------

  test "draft listing can be submitted for review" do
    listing = listings(:draft)
    listing.submit_for_review!
    assert_equal "pending_review", listing.status
  end

  test "pending listing can be approved and records a moderation event" do
    listing = listings(:pending)
    assert_difference -> { listing.moderation_events.count }, 1 do
      listing.approve!(users(:admin))
    end
    assert_predicate listing, :approved?
    assert_not_nil listing.published_at
    assert_equal users(:admin), listing.moderation_events.last.admin
  end

  test "approved listing cannot be approved again" do
    assert_raises(Listing::InvalidTransition) { listings(:gigabyte).approve!(users(:admin)) }
  end

  test "approved listing cannot be submitted for review" do
    assert_raises(Listing::InvalidTransition) { listings(:gigabyte).submit_for_review! }
  end

  test "pending listing can be rejected with a reason by an admin" do
    listing = listings(:pending)
    assert_difference -> { listing.moderation_events.count }, 1 do
      listing.reject!("photos too small", admin: users(:admin))
    end
    assert_predicate listing, :rejected?
    assert_equal "photos too small", listing.rejection_reason
    event = listing.moderation_events.last
    assert_equal users(:admin), event.admin
    refute_equal listing.user, event.admin
    assert_equal "photos too small", event.note
  end

  test "reject without a reason raises" do
    assert_raises(Listing::InvalidTransition) { listings(:pending).reject!("", admin: users(:admin)) }
  end

  test "rejected listing can be resubmitted" do
    listing = listings(:rejected)
    listing.submit_for_review!
    assert_equal "pending_review", listing.status
    assert_nil listing.rejection_reason
  end

  test "approved listing can be sold" do
    listing.mark_sold!
    assert_predicate listing, :sold?
    assert_not_nil listing.sold_at
  end

  test "sold listing cannot be sold again" do
    listing.mark_sold!
    assert_raises(Listing::InvalidTransition) { listing.mark_sold! }
  end

  test "draft listing cannot be sold" do
    assert_raises(Listing::InvalidTransition) { listings(:draft).mark_sold! }
  end

  # --- money and validations --------------------------------------------------

  test "price is a Money built from the cents column" do
    assert_kind_of Money, listing.price
    assert_equal 59999, listing.price.cents
    assert_equal BigDecimal("599.99"), listing.price.amount
  end

  test "price_cents must be a positive integer" do
    listing.price_cents = 0
    assert_not listing.valid?
    assert_includes listing.errors[:price_cents], "must be greater than 0"
  end

  test "discount_percent is derived from the original price" do
    listing.original_price_cents = 80000
    assert_equal 25, listing.discount_percent
  end

  test "an empty specs hash is valid (accessories and games have no specs)" do
    other = Listing.new(user: users(:one), category: categories(:gpus), title: "Mousepad XL",
                        price_cents: 900, condition: :brand_new, specs: {})
    assert other.valid?, other.errors.full_messages.to_sentence
    assert_not_includes other.errors.attribute_names, :specs
  end

  test "non-hash specs are invalid" do
    other = Listing.new(user: users(:one), category: categories(:gpus), title: "Mousepad XL",
                        price_cents: 900, condition: :brand_new, specs: nil)
    assert_not other.valid?
    assert_includes other.errors[:specs], I18n.t("errors.messages.invalid")
  end

  # --- search -----------------------------------------------------------------

  test "search_text finds by title" do
    assert_includes Listing.search_text("gigabyte"), listing
    refute_includes Listing.search_text("gigabyte"), listings(:draft)
  end

  test "search_text finds by description" do
    assert_includes Listing.search_text("sealed"), listing
  end

  test "search_text reindexes on update" do
    listing.update!(title: "Quantum Flux Capacitor")
    assert_includes Listing.search_text("quantum"), listing
  end

  # --- photos -----------------------------------------------------------------

  test "more than twelve photos is invalid" do
    13.times { |i| attach_photo(listing, "photo#{i}.jpg") }
    assert_not listing.valid?
    assert_includes listing.errors[:photos],
      I18n.t("activerecord.errors.messages.photo_limit_exceeded", count: Listing::MAX_PHOTOS)
  end

  test "unsupported photo content type is invalid" do
    attach_photo(listing, "virus.exe", "data", "application/x-msdownload")
    assert_not listing.valid?
    assert_includes listing.errors[:photos], I18n.t("activerecord.errors.messages.photo_content_type_invalid")
  end

  test "photo larger than ten megabytes is invalid" do
    attach_photo(listing, "big.jpg", "x" * (Listing::MAX_PHOTO_BYTES + 1))
    assert_not listing.valid?
    assert_includes listing.errors[:photos],
      I18n.t("activerecord.errors.messages.photo_too_large", max: Listing::MAX_PHOTO_BYTES / 1.megabyte)
  end

  private

  def attach_photo(record, filename, body = "data", content_type = "image/jpeg")
    record.photos.attach(
      io: StringIO.new(body),
      filename: filename,
      content_type: content_type
    )
  end
end
