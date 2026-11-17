require "test_helper"

class Admin::ListingsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index filters by status and country" do
    get admin_listings_path(status: "approved", country: "ES")
    assert_response :success
    assert_match listings(:gigabyte).title, response.body
    assert_no_match listings(:pending).title, response.body
  end

  test "csv export streams the filtered set with a header row" do
    get admin_listings_path(format: :csv, status: "approved")
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match /attachment; filename="pcmarket-listings-#{Date.current}\.csv"/,
                 response.headers["Content-Disposition"]

    rows = response.body.lines
    assert_match(/title/, rows.first)
    titles = rows.first(20).join
    assert_match listings(:gigabyte).title, titles
    assert_no_match listings(:pending).title, titles
  end

  test "admin edit can change status and records an unpublish event" do
    listing = listings(:gigabyte) # approved

    assert_difference [ -> { ModerationEvent.count }, -> { AdminAuditLog.count } ], 1 do
      patch admin_listing_path(listing), params: { listing: { status: "pending_review" } }
      assert_response :redirect
    end

    assert_equal "pending_review", listing.reload.status
    assert_equal "unpublished", listing.moderation_events.order(:id).last.action

    follow_redirect!
    assert_match I18n.t("admin.listings.update.updated", title: listing.title), flash[:notice]
  end

  test "admin edit surfaces validation errors" do
    patch admin_listing_path(listings(:gigabyte)), params: { listing: { title: "" } }
    assert_response :unprocessable_entity
  end

  test "unpublish archives an approved listing with its own event" do
    listing = listings(:gigabyte)

    assert_difference [ -> { ModerationEvent.count }, -> { AdminAuditLog.count } ], 1 do
      post admin_listing_unpublication_path(listing)
      assert_response :redirect
    end

    assert_equal "archived", listing.reload.status
    assert_equal "unpublished", listing.moderation_events.order(:id).last.action
  end

  test "unpublish on a sold listing is refused" do
    post admin_listing_unpublication_path(listings(:sold))
    follow_redirect!
    assert_match I18n.t("admin.unpublications.create.not_unpublishable"), flash[:alert]
    assert_predicate listings(:sold).reload, :sold?
  end

  test "destroy is allowed for drafts and denied for live listings" do
    delete admin_listing_path(listings(:draft))
    assert_response :redirect
    assert_not Listing.exists?(listings(:draft).id)

    delete admin_listing_path(listings(:gigabyte))
    assert_response :unprocessable_entity
    assert_match I18n.t("admin.listings.destroy.destroy_denied"), response.body
    assert Listing.exists?(listings(:gigabyte).id)
  end

  test "global search finds listings users and orders" do
    get admin_search_path(q: "Gigabyte")
    assert_response :success
    assert_match listings(:gigabyte).title, response.body

    get admin_search_path(q: "one@example.com")
    assert_response :success
    assert_match users(:one).email_address, response.body

    get admin_search_path(q: "a")
    assert_response :success
    assert_match I18n.t("admin.searches.show.too_short"), response.body
  end
end
