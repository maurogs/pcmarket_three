require "test_helper"

class Sell::ListingsTest < ActionDispatch::IntegrationTest
  # user one owns gigabyte (approved), sold, pending; user two owns as_new
  # (approved), draft, rejected. Both already have stores. "fresh" has none.
  setup do
    @fresh = User.create!(
      email_address: "fresh@example.com",
      password_digest: BCrypt::Password.create("password"),
      username: "fresh",
      first_name: "Fresh",
      last_name: "Seller",
      confirmed_at: Time.current
    )
  end

  def form_params(overrides = {})
    {
      listing: {
        title: "Second hand RX 6700 XT",
        description: "Works great, small scratches on the backplate",
        condition: "used_good",
        quantity: "1",
        price: "180",
        category_root: "graphics-cards",
        city: "Madrid",
        region: "Madrid",
        postal_code: "28001",
        specs: { "vram" => "8GB", "negotiable" => "true" }
      },
      intent: "draft"
    }.deep_merge(overrides)
  end

  # --- auth ---------------------------------------------------------------

  test "guests are sent to sign in from the sell area" do
    get sell_listings_path
    assert_redirected_to new_session_path
  end

  test "banned sellers are blocked from the sell area" do
    sign_in_as users(:banned)
    get sell_listings_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match "account is suspended", response.body
  end

  # --- index --------------------------------------------------------------

  test "index only shows the signed-in seller's own listings" do
    sign_in_as users(:one)
    get sell_listings_path
    assert_response :success
    assert_match "Gigabyte RTX 4070 Gaming OC", response.body
    assert_no_match(/Used RTX 3080/, response.body) # user two's draft
  end

  test "index tab filters rejected listings and shows the rejection reason" do
    sign_in_as users(:two)
    get sell_listings_path(tab: "rejected")
    assert_response :success
    assert_match "Rejected GPU Listing", response.body
    assert_match "Photos unreadable", response.body
  end

  # --- create -------------------------------------------------------------

  test "new form renders category picker and province select" do
    sign_in_as @fresh
    get new_sell_listing_path
    assert_response :success
    assert_match "listing[category_root]", response.body
    assert_match "listing[region]", response.body
    assert_match "Madrid", response.body
  end

  test "saving a draft creates the listing and a personal store" do
    sign_in_as @fresh
    assert_difference -> { Listing.count }, 1 do
      assert_difference -> { Store.count }, 1 do
        post sell_listings_path, params: form_params
      end
    end

    listing = Listing.order(:id).last
    assert_equal @fresh, listing.user
    assert_predicate listing, :draft?
    assert_equal "fresh", listing.store.name
    assert_predicate listing.store, :individual?
    assert_redirected_to edit_sell_listing_path(listing)
    follow_redirect!
    assert_match "Draft saved", response.body
  end

  test "submit button sends the listing to review and notifies every admin" do
    sign_in_as users(:two)
    assert_difference -> { Notification.where(kind: "listing_submitted").count }, 1 do
      post sell_listings_path, params: form_params(intent: "submit")
    end

    listing = Listing.order(:id).last
    assert_predicate listing, :pending_review?
    assert Notification.exists?(user: users(:admin), kind: "listing_submitted")
  end

  test "creating without a category re-renders the form with errors" do
    sign_in_as @fresh
    assert_no_difference -> { Listing.count } do
      post sell_listings_path, params: form_params(listing: { category_root: "" })
    end
    assert_response :unprocessable_entity
    assert_match "Please fix", response.body
  end

  # --- scoping ------------------------------------------------------------

  test "another seller's listing is a 404 across the sell area" do
    sign_in_as users(:one)
    get edit_sell_listing_path(listings(:as_new))
    assert_response :not_found
    delete sell_listing_path(listings(:as_new))
    assert_response :not_found
    post sell_listing_submission_path(listings(:as_new))
    assert_response :not_found
  end

  # --- update: material vs price-only edits --------------------------------

  test "a material edit to a live listing sends it back to review" do
    sign_in_as users(:two)
    # Only the material field is touched; everything else stays as-is
    # (the form always submits the category chain, so keep rtx).
    patch sell_listing_path(listings(:as_new)), params:
      { listing: { title: "Barely used RTX 4060 Ti", category_root: "rtx-series" }, intent: "draft" }

    assert_predicate listings(:as_new).reload, :pending_review?
    follow_redirect!
    assert_match "sent back to review", response.body
  end

  test "a price-only edit keeps a live listing live" do
    sign_in_as users(:two)
    patch sell_listing_path(listings(:as_new)), params:
      { listing: { price: "290", category_root: "rtx-series" }, intent: "draft" }

    listing = listings(:as_new).reload
    assert_predicate listing, :approved?
    assert_equal 29000, listing.price_cents
  end

  # --- status transitions --------------------------------------------------

  test "a draft can be submitted for review from the index action" do
    sign_in_as users(:two)
    assert_difference -> { Notification.where(kind: "listing_submitted").count }, 1 do
      post sell_listing_submission_path(listings(:draft))
    end
    assert_predicate listings(:draft).reload, :pending_review?
    assert_redirected_to sell_listings_path(tab: "pending_review")
  end

  test "an approved listing can be archived and marked sold" do
    sign_in_as users(:one)
    post sell_listing_archival_path(listings(:gigabyte))
    assert_predicate listings(:gigabyte).reload, :archived?

    post sell_listing_sale_mark_path(listings(:pending)) # invalid transition
    assert_predicate listings(:pending).reload, :pending_review?
    assert_redirected_to sell_listings_path

    post sell_listing_sale_mark_path(listings(:sold)) # already sold
    assert_redirected_to sell_listings_path
  end

  # --- destroy --------------------------------------------------------------

  test "draft listings can be deleted but live ones cannot" do
    sign_in_as users(:two)
    assert_difference -> { Listing.count }, -1 do
      delete sell_listing_path(listings(:draft))
    end
    assert_redirected_to sell_listings_path(tab: "all")

    assert_no_difference -> { Listing.count } do
      delete sell_listing_path(listings(:as_new))
    end
    assert_response :unprocessable_entity
    assert_match "cannot be deleted", response.body
  end

  # --- photo validation ------------------------------------------------------

  test "non-image uploads are rejected with a friendly message" do
    sign_in_as users(:two)
    file = Rack::Test::UploadedFile.new(StringIO.new("definitely not an image"), "text/plain",
                                        original_filename: "notes.txt")
    post sell_listings_path, params: form_params(listing: { photos: [ file ] })
    assert_response :unprocessable_entity
    assert_match "must be a JPEG, PNG or WebP image", response.body
  end

  test "oversized photos are rejected with the limit spelled out" do
    sign_in_as users(:two)
    file = Rack::Test::UploadedFile.new(StringIO.new("x" * (Listing::MAX_PHOTO_BYTES + 1)), "image/jpeg",
                                        original_filename: "huge.jpg")
    post sell_listings_path, params: form_params(listing: { photos: [ file ] })
    assert_response :unprocessable_entity
    assert_match "must be 10 MB or smaller", response.body
  end

  # --- spec validation --------------------------------------------------------

  test "unknown spec keys are rejected even for drafts" do
    sign_in_as users(:two)
    post sell_listings_path, params: form_params(listing: { specs: { "moonphase" => "waxing" } })
    assert_response :unprocessable_entity
    assert_match "unknown specification", response.body
  end

  test "invalid values for known specs are rejected on submission" do
    sign_in_as users(:two)
    post sell_listings_path, params:
      form_params(intent: "submit", listing: { specs: { "vram" => "40GB", "negotiable" => "true" } })
    assert_response :unprocessable_entity
    assert_match "VRAM has an invalid value", response.body
  end

  test "required specs are only enforced when submitting for review" do
    sign_in_as users(:two)

    # Draft: missing the required "negotiable" spec saves fine.
    assert_difference -> { Listing.count }, 1 do
      post sell_listings_path, params: form_params(listing: { specs: { "negotiable" => nil } })
    end
    listing = Listing.order(:id).last

    # Submitting it now fails on the missing required spec.
    assert_no_difference -> { Notification.where(kind: "listing_submitted").count } do
      post sell_listing_submission_path(listing)
    end
    assert_predicate listing.reload, :draft?
    follow_redirect!
    assert_match "Negotiable is required", response.body
  end

  # --- dynamic category fields -------------------------------------------------

  test "category fields endpoint renders spec inputs inside the turbo frame" do
    sign_in_as users(:two)
    get sell_category_field_path("rtx-series")
    assert_response :success
    assert_match 'turbo-frame id="spec_fields"', response.body
    assert_match "listing[specs][vram]", response.body
    assert_match "listing[specs][negotiable]", response.body
  end
end
