require "test_helper"

class OffersTest < ActionDispatch::IntegrationTest
  setup do
    @listing = listings(:gigabyte) # seller users(:one), 599,99 €
  end

  # --- the form ------------------------------------------------------------

  test "guests are sent to sign in before the offer form" do
    get new_listing_offer_path(@listing)
    assert_redirected_to new_session_path
  end

  test "buyers see the form with the minimum hint; owners get a 404" do
    sign_in_as users(:two)
    get new_listing_offer_path(@listing)
    assert_response :success
    assert_match I18n.t("offers.new.title"), response.body
    assert_match "€300.00", response.body # 50% minimum hint

    sign_in_as users(:one)
    get new_listing_offer_path(@listing)
    assert_response :not_found
  end

  test "the form is hidden on offer-less and unapproved listings" do
    @listing.store.update!(allow_offers_default: false)
    sign_in_as users(:two)
    get listing_path(@listing)
    assert_response :success
    assert_select "a[href='#{new_listing_offer_path(@listing)}']", count: 0

    @listing.store.update!(allow_offers_default: true)
    get listing_path(listings(:pending))
    assert_select "a[href='#{new_listing_offer_path(listings(:pending))}']", count: 0
  end

  test "message seller button lives on the listing page for non-owners" do
    sign_in_as users(:two)
    get listing_path(@listing)
    assert_response :success
    assert_select "form[action='#{conversations_path}']", minimum: 1

    sign_in_as users(:one)
    get listing_path(@listing)
    assert_select "form[action='#{conversations_path}']", count: 0
  end

  # --- creating offers -------------------------------------------------------

  test "a valid offer is created, announced in chat and redirects to the thread" do
    sign_in_as users(:two)
    post listing_offers_path(@listing), params: { offer: { amount: "350" } }

    offer = Offer.sole
    assert_equal 35_000, offer.amount_cents
    assert_redirected_to conversation_path(offer.conversation)
    assert_equal I18n.t("offers.create.created"), flash[:notice]
    assert Message.exists?(offer: offer, kind: :offer)
    assert Notification.exists?(user: users(:one), kind: "new_offer")
  end

  test "below the minimum the form re-renders 422 with the floor amount" do
    sign_in_as users(:two)
    post listing_offers_path(@listing), params: { offer: { amount: "100" } }

    assert_response :unprocessable_entity
    assert_match I18n.t("offers.create.errors.below_minimum", min: "€300.00"), response.body
    assert_empty Offer.all
  end

  test "garbage amounts come back as invalid" do
    sign_in_as users(:two)
    post listing_offers_path(@listing), params: { offer: { amount: "cien euros" } }

    assert_response :unprocessable_entity
    assert_match I18n.t("offers.create.errors.invalid"), response.body
  end

  # --- decisions -------------------------------------------------------------

  test "the seller accepts: reservation, auto-decline, notification" do
    offer = place_offer(users(:two), 35_000)
    other = place_offer(users(:admin), 40_000)

    sign_in_as users(:one)
    post offer_acceptance_path(offer)

    assert_redirected_to conversation_path(offer.conversation)
    assert_equal I18n.t("acceptances.create.accepted"), flash[:notice]
    assert_predicate offer.reload, :accepted?
    assert_predicate other.reload, :declined?
    @listing.reload
    assert_predicate @listing, :reserved?
    assert_equal users(:two), @listing.reserved_for
    assert Notification.exists?(user: users(:two), kind: "offer_accepted")
  end

  test "reserved listings refuse new offers and show the buyer a reserved banner" do
    until_time = Time.current + 12.hours
    @listing.update!(status: :reserved, reserved_for: users(:two), reserved_until: until_time)

    get listing_path(@listing)
    assert_response :success
    assert_match I18n.t("listings.show.reserved_banner", until_time: I18n.l(until_time.to_date, format: :long)),
                 response.body

    sign_in_as users(:admin)
    post listing_offers_path(@listing), params: { offer: { amount: "350" } }
    assert_response :unprocessable_entity
    assert_match I18n.t("offers.create.errors.not_allowed"), response.body
  end

  test "seller declines; buyer withdraws; stale decisions flash instead of breaking" do
    offer = place_offer(users(:two), 35_000)

    sign_in_as users(:one)
    post offer_decline_path(offer)
    assert_equal I18n.t("declines.create.declined"), flash[:notice]
    assert_predicate offer.reload, :declined?

    post offer_decline_path(offer)
    assert_redirected_to conversation_path(offer.conversation)
    assert_equal I18n.t("offers.decisions.stale"), flash[:alert]

    second = place_offer(users(:two), 30_000)
    sign_in_as users(:two)
    post offer_withdrawal_path(second)
    assert_equal I18n.t("withdrawals.create.withdrawn"), flash[:notice]
    assert_predicate second.reload, :withdrawn?
  end

  test "outsiders 404 on every decision route" do
    offer = place_offer(users(:two), 35_000)

    sign_in_as users(:admin) # neither buyer nor seller of this offer
    post offer_acceptance_path(offer)
    assert_response :not_found
    post offer_decline_path(offer)
    assert_response :not_found

    sign_in_as users(:one)
    post offer_withdrawal_path(offer) # buyer-only route
    assert_response :not_found
  end

  # --- offers inbox tabs -------------------------------------------------------

  test "received and sent tabs show the right offers with counts" do
    offer = place_offer(users(:two), 35_000)

    sign_in_as users(:one)
    get offers_path
    assert_response :success
    assert_match I18n.t("offers.row.from", buyer: users(:two).display_name), response.body
    assert_select "form[action='#{offer_acceptance_path(offer)}']", minimum: 1
    assert_select "form[action='#{offer_withdrawal_path(offer)}']", count: 0

    sign_in_as users(:two)
    get offers_path(tab: "sent")
    assert_response :success
    assert_select "form[action='#{offer_withdrawal_path(offer)}']", minimum: 1
    assert_select "form[action='#{offer_acceptance_path(offer)}']", count: 0
  end

  private

    def place_offer(buyer, cents)
      Offers::Create.call(listing: @listing, buyer: buyer, amount_cents: cents).offer
    end
end
