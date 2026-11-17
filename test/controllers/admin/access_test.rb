require "test_helper"

class Admin::AccessTest < ActionDispatch::IntegrationTest
  # One entry per distinct admin controller/action surface. Non-admins must
  # 404 (never 403): confirming the panel exists is itself a leak.
  def admin_get_pages
    {
      admin_root_path => :get,
      admin_dashboard_path => :get,
      admin_search_path(q: "rtx") => :get,
      admin_moderations_path => :get,
      admin_moderation_path(listings(:pending)) => :get,
      admin_listings_path => :get,
      admin_listing_path(listings(:gigabyte)) => :get,
      edit_admin_listing_path(listings(:gigabyte)) => :get,
      new_admin_listing_rejection_path(listings(:pending)) => :get,
      admin_users_path => :get,
      admin_user_path(users(:one)) => :get,
      edit_admin_user_path(users(:one)) => :get,
      new_admin_user_ban_path(users(:one)) => :get,
      admin_stores_path => :get,
      admin_store_path(stores(:one)) => :get,
      edit_admin_store_path(stores(:one)) => :get
    }
  end

  test "anonymous visitors are sent to the login page" do
    get admin_dashboard_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "regular users get 404 on every admin page" do
    sign_in_as users(:two)

    admin_get_pages.each do |path, verb|
      send verb, path
      assert_response :not_found, "#{path} should 404 for a regular user"
    end
  end

  test "regular users get 404 on admin writes too" do
    sign_in_as users(:two)

    post admin_listing_approval_path(listings(:pending))
    assert_response :not_found

    post admin_user_ban_path(users(:one))
    assert_response :not_found

    post admin_store_verification_path(stores(:one))
    assert_response :not_found

    post admin_bulk_moderation_path, params: { listing_ids: [ listings(:pending).id ], decision: "approve" }
    assert_response :not_found

    post admin_listing_rejection_path(listings(:pending)), params: { reason: "other" }
    assert_response :not_found

    post admin_listing_unpublication_path(listings(:gigabyte))
    assert_response :not_found

    patch admin_listing_path(listings(:gigabyte)), params: { listing: { title: "Hijacked title" } }
    assert_response :not_found

    delete admin_listing_path(listings(:gigabyte))
    assert_response :not_found

    post admin_user_impersonation_path(users(:one))
    assert_response :not_found

    patch admin_user_path(users(:one)), params: { user: { role: "user" } }
    assert_response :not_found

    post admin_store_hiding_path(stores(:one))
    assert_response :not_found

    patch admin_store_path(stores(:one)), params: { store: { name: "Hijacked store" } }
    assert_response :not_found

    # Nothing above may have changed any state.
    assert Listing.where(id: listings(:pending).id).where(status: :approved).none?
    assert_nil users(:one).reload.banned_at
    assert_equal "user", users(:one).role
    assert_equal listings(:gigabyte).title, listings(:gigabyte).reload.title
    assert_not listings(:gigabyte).archived?
    assert_not stores(:one).reload.hidden?
    assert_equal stores(:one).name, stores(:one).reload.name
    assert_not stores(:one).verified?
    assert_equal 0, Session.where(user_id: users(:one).id).count
  end

  test "admins get through and the layout is the admin one" do
    sign_in_as users(:admin)

    get admin_dashboard_path
    assert_response :success
    assert_select "h1", text: I18n.t("admin.dashboards.show.title")
  end
end
