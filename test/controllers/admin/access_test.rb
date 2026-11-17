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
      edit_admin_store_path(stores(:one)) => :get,
      # Phase 6b surfaces.
      admin_orders_path => :get,
      admin_order_path(orders(:one)) => :get,
      admin_disputes_path => :get,
      admin_dispute_path(orders(:one)) => :get,
      new_admin_dispute_resolution_path(orders(:one)) => :get,
      admin_reviews_path => :get,
      admin_categories_path => :get,
      new_admin_category_path => :get,
      edit_admin_category_path(categories(:rtx)) => :get,
      admin_category_spec_attributes_path(categories(:gpus)) => :get,
      admin_spec_attributes_path => :get,
      new_admin_spec_attribute_path => :get,
      edit_admin_spec_attribute_path(spec_attributes(:vram)) => :get,
      admin_labels_path => :get,
      new_admin_label_path => :get,
      edit_admin_label_path(labels(:open_box)) => :get,
      admin_seller_tags_path => :get,
      new_admin_seller_tag_path => :get,
      edit_admin_seller_tag_path(seller_tags(:watercooled)) => :get,
      admin_countries_path => :get,
      edit_admin_country_path(countries(:gb)) => :get,
      admin_feature_flags_path => :get,
      edit_admin_settings_path => :get,
      admin_legal_pages_path => :get,
      new_admin_legal_page_path => :get,
      edit_admin_legal_page_path(access_legal_page) => :get,
      admin_newsletter_subscriptions_path => :get,
      admin_audit_logs_path => :get
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

    # --- Phase 6b write routes (same rule: 404 + no state change) ---------
    category_count = Category.count
    spec_option_count = SpecOption.count
    label_count = Label.count
    seller_tag_count = SellerTag.count
    legal_page_count = LegalPage.count
    join_count = CategorySpecAttribute.count

    patch admin_order_path(orders(:one)), params: { order: { status: "cancelled", reason: "hijack" } }
    assert_response :not_found

    post admin_order_notes_path(orders(:one)), params: { order_note: { body: "Hijacked note" } }
    assert_response :not_found

    post admin_dispute_resolution_path(orders(:one)), params: { resolution: { action: "refund" } }
    assert_response :not_found

    delete admin_review_path(access_review)
    assert_response :not_found

    post admin_categories_path, params: { category: { names: { "en" => "Hijacked category" } } }
    assert_response :not_found

    patch admin_category_path(categories(:rtx)), params: { category: { active: false } }
    assert_response :not_found

    post admin_category_position_path(categories(:rtx)), params: { direction: "up" }
    assert_response :not_found

    post admin_category_spec_attributes_path(categories(:rtx)),
         params: { category_spec_attribute: { spec_attribute_id: spec_attributes(:vram).id } }
    assert_response :not_found

    post admin_spec_attributes_path, params: { spec_attribute: { key: "hijacked", names: { "en" => "Hijacked" } } }
    assert_response :not_found

    post admin_spec_attribute_spec_options_path(spec_attributes(:vram)),
         params: { spec_option: { value: "hijacked" } }
    assert_response :not_found

    delete admin_spec_attribute_spec_option_path(spec_attributes(:vram), spec_options(:vram_8))
    assert_response :not_found

    post admin_spec_attribute_spec_option_merge_path(spec_attributes(:vram), spec_options(:vram_8)),
         params: { merge: { target_id: spec_options(:vram_12).id } }
    assert_response :not_found

    post admin_labels_path, params: { label: { color: "#ff0000", names: { "en" => "Hijacked label" } } }
    assert_response :not_found

    post admin_seller_tags_path, params: { seller_tag: { names: { "en" => "Hijacked tag" } } }
    assert_response :not_found

    patch admin_country_path(countries(:gb)), params: { country: { enabled: true } }
    assert_response :not_found

    patch admin_feature_flag_path("commissions"), params: { switch: "on" }
    assert_response :not_found

    patch admin_settings_path, params: { settings: { commission_percent: "15" } }
    assert_response :not_found

    post admin_legal_pages_path,
         params: { legal_page: { country_code: "ES", locale: "en", slug: "cookies", title: "Hijacked", body: "x" } }
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

    # 6b state: every touched model must be untouched.
    assert_equal "completed", orders(:one).reload.status
    assert_equal 0, OrderNote.count
    assert_nil access_review.reload.hidden_at
    assert_equal category_count, Category.count
    assert Category.friendly.find("rtx-series").active
    assert_equal join_count, CategorySpecAttribute.count
    assert_equal spec_option_count, SpecOption.count
    assert SpecOption.exists?(spec_options(:vram_8).id)
    assert_equal label_count, Label.count
    assert_equal seller_tag_count, SellerTag.count
    assert_not countries(:gb).reload.enabled?
    assert_not Flipper.enabled?(:commissions)
    assert_nil Setting.get("commission_percent") # nothing was written
    assert_equal legal_page_count, LegalPage.count
  end

  test "admins get through and the layout is the admin one" do
    sign_in_as users(:admin)

    get admin_dashboard_path
    assert_response :success
    assert_select "h1", text: I18n.t("admin.dashboards.show.title")
  end

  private

  # Records needed to address the edit/show routes for surfaces with no
  # fixtures. Created lazily; the write test asserts they stay untouched.
  def access_legal_page
    @access_legal_page ||= LegalPage.create!(country_code: "ES", locale: "en", slug: "terms",
                                             title: "Terms", body: "Terms body", published: true)
  end

  def access_review
    @access_review ||= Review.create!(order: orders(:one), reviewer: users(:one),
                                      store: stores(:one), seller: users(:one),
                                      rating: 4, body: "Keep me")
  end
end
