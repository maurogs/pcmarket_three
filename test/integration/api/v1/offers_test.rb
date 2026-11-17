require "test_helper"

# Offers: creation goes through Offers::Create, decisions through the service
# objects, and the role rules are the web's — sellers decide, buyers withdraw,
# outsiders 404.
class Api::V1::OffersTest < ActionDispatch::IntegrationTest
  setup do
    @seller = users(:one)
    @buyer = users(:two)
    @outsider = users(:admin)
    @listing = listings(:gigabyte)
  end

  test "creating an offer delegates to Offers::Create and returns the offer" do
    auth_as @buyer

    assert_difference -> { Offer.count }, 1 do
      post "/api/v1/listings/#{@listing.id}/offers",
           params: { amount_cents: 45_000, message: "recojo hoy mismo" }.to_json,
           headers: json_api_headers
    end
    assert_response :created

    offer = json_body[:offer]
    assert_equal 45_000, offer[:amount_money][:cents]
    assert_equal @listing.currency, offer[:amount_money][:currency]
    assert_equal "pending", offer[:status]
    assert_equal @seller.id, offer[:seller][:id]
    assert_equal @listing.slug, offer[:listing][:slug]

    created = Offer.last
    assert_equal @listing.id, created.listing_id
    assert_not_nil created.conversation, "the thread is created by the service"
  end

  test "an offer below the minimum keeps the web's localized message" do
    auth_as @buyer

    post "/api/v1/listings/#{@listing.id}/offers",
         params: { amount_cents: 1 }.to_json, headers: json_api_headers

    assert_response :unprocessable_entity
    body = json_body[:error]
    assert_equal "invalid_request", body[:code]
    minimum = Money.new(Offers::Create.minimum_for(@listing), @listing.currency)
    assert_equal I18n.t("offers.create.errors.below_minimum", min: minimum.formatted), body[:message]
  end

  test "a new offer replaces the buyer's previous pending one" do
    auth_as @buyer
    post "/api/v1/listings/#{@listing.id}/offers", params: { amount_cents: 45_000 }.to_json,
                                                  headers: json_api_headers
    assert_response :created
    first_id = json_body[:offer][:id]

    post "/api/v1/listings/#{@listing.id}/offers", params: { amount_cents: 46_000 }.to_json,
                                                  headers: json_api_headers
    assert_response :created
    assert_equal 2, Offer.count
    assert_predicate Offer.find(first_id).reload, :withdrawn?,
                     "one pending offer per buyer, always (Offers::Create)"
  end

  test "an offer at or above the asking price is refused" do
    auth_as @buyer

    post "/api/v1/listings/#{@listing.id}/offers",
         params: { amount_cents: @listing.price_cents }.to_json, headers: json_api_headers
    assert_response :unprocessable_entity
    assert_equal I18n.t("offers.create.errors.above_price"), json_body[:error][:message]
  end

  test "an offer on a listing that disallows offers is rejected" do
    @listing.update_column(:allow_offers, false)
    auth_as @buyer

    post "/api/v1/listings/#{@listing.id}/offers", params: { amount_cents: 45_000 }.to_json,
                                                  headers: json_api_headers
    assert_response :unprocessable_entity
    assert_equal I18n.t("offers.create.errors.not_allowed"), json_body[:error][:message]
  end

  test "the owner is pointed at a different listing, a third-party buyer is welcome" do
    auth_as @seller
    post "/api/v1/listings/#{@listing.id}/offers", params: { amount_cents: 45_000 }.to_json,
                                                  headers: json_api_headers
    assert_response :not_found
    assert_equal 0, Offer.count

    auth_as @outsider
    post "/api/v1/listings/#{@listing.id}/offers", params: { amount_cents: 50_000 }.to_json,
                                                  headers: json_api_headers
    assert_response :created
    assert_equal @outsider.id, Offer.last.buyer_id
  end

  test "the seller accepts: the listing is reserved for the buyer" do
    offer = create_offer(45_000)
    auth_as @seller

    post "/api/v1/offers/#{offer.id}/acceptance", headers: json_api_headers
    assert_response :success

    offer.reload
    assert_predicate offer, :accepted?
    @listing.reload
    assert_predicate @listing, :reserved?
    assert_equal @buyer.id, @listing.reserved_for_id

    body = json_body
    assert_equal offer.id, body[:offer][:id]
    assert_equal "accepted", body[:offer][:status]
    assert body[:message].present?
  end

  test "accepting an already decided offer is a conflict" do
    offer = create_offer(45_000)
    Offers::Decline.call(offer: offer)

    auth_as @seller
    post "/api/v1/offers/#{offer.id}/acceptance", headers: json_api_headers
    assert_response :conflict
    assert_equal "stale_transition", json_body[:error][:code]
  end

  test "accepting is the seller's decision: the buyer is refused, strangers 404" do
    offer = create_offer(45_000)

    auth_as @buyer
    post "/api/v1/offers/#{offer.id}/acceptance", headers: json_api_headers
    assert_response :forbidden
    assert_equal "forbidden", json_body[:error][:code]
    assert_predicate offer.reload, :pending?

    auth_as @outsider
    post "/api/v1/offers/#{offer.id}/acceptance", headers: json_api_headers
    assert_response :not_found
  end

  test "the seller declines and the listing stays on sale" do
    offer = create_offer(45_000)
    auth_as @seller

    post "/api/v1/offers/#{offer.id}/decline", headers: json_api_headers
    assert_response :success

    assert_predicate offer.reload, :declined?
    assert_equal "declined", json_body[:offer][:status]
    assert_predicate @listing.reload, :approved?
  end

  test "a competing pending offer is auto-declined when the seller accepts" do
    first = create_offer(45_000)
    Conversation.create!(listing: @listing, buyer: @outsider, seller: @seller)
    rival = Offer.create!(listing: @listing, buyer: @outsider, amount_cents: 48_000)

    auth_as @seller
    post "/api/v1/offers/#{first.id}/acceptance", headers: json_api_headers
    assert_response :success

    assert_predicate rival.reload, :declined?
    assert_predicate @listing.reload, :reserved?
  end

  test "the buyer withdraws an offer" do
    offer = create_offer(45_000)
    auth_as @buyer

    post "/api/v1/offers/#{offer.id}/withdrawal", headers: json_api_headers
    assert_response :success
    assert_predicate offer.reload, :withdrawn?
    assert_equal "withdrawn", json_body[:offer][:status]
  end

  test "withdrawing is the buyer's move: the seller is refused" do
    offer = create_offer(45_000)
    auth_as @seller

    post "/api/v1/offers/#{offer.id}/withdrawal", headers: json_api_headers
    assert_response :forbidden
    assert_predicate offer.reload, :pending?
  end

  test "offers are listed per role and scoped to the caller" do
    mine = create_offer(45_000)
    Conversation.create!(listing: listings(:featured), buyer: @outsider, seller: @seller)
    foreign = Offer.create!(listing: listings(:featured), buyer: @outsider, amount_cents: 42_000)

    auth_as @seller
    get "/api/v1/offers", params: { role: "received" }, headers: json_api_headers
    assert_response :success
    assert_equal [ mine.id, foreign.id ].sort, json_body[:offers].map { |o| o[:id] }.sort

    auth_as @buyer
    get "/api/v1/offers", params: { role: "received" }, headers: json_api_headers
    assert_empty json_body[:offers], "the buyer receives offers on their own listings only"

    get "/api/v1/offers", params: { role: "sent" }, headers: json_api_headers
    assert_equal [ mine.id ], json_body[:offers].map { |o| o[:id] }
  end

  private

  def create_offer(amount)
    Offers::Create.call(listing: @listing, buyer: @buyer, amount_cents: amount).offer
  end
end
