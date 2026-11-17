require "test_helper"

# Renders EVERY admin GET page as a real admin and asserts it responds 200
# with no untranslated text. Exists because per-action tests only cover the
# happy data they set up — this is the whole-panel smoke test that catches
# broken helpers, enum-label lookups and missing locale keys (reviewer bug:
# /en/admin/listings crashed on photo_variant_tag's missing class: option).
class Admin::PageRenderTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @disputed = disputed_order
    @legal_page = legal_page
    @report = open_report
    @contact_message = contact_message
  end

  # Every GET route in the admin namespace (index/new/show/edit for each
  # resource, ids from fixtures where one exists). Key = human page name,
  # mirrored by PAGE_NAMES below (guarded by the sync test).
  def admin_pages
    {
      "dashboard root"             => admin_root_path,
      "dashboard"                  => admin_dashboard_path,
      "global search"              => admin_search_path(q: "rtx"),
      "moderation queue"           => admin_moderations_path,
      "moderation cockpit"         => admin_moderation_path(listings(:pending)),
      "listings index"             => admin_listings_path,
      "listings index filtered"    => admin_listings_path(status: "approved", country: "ES"),
      "listing show"               => admin_listing_path(listings(:gigabyte)),
      "listing edit"               => edit_admin_listing_path(listings(:gigabyte)),
      "rejection form"             => new_admin_listing_rejection_path(listings(:pending)),
      "users index"                => admin_users_path,
      "user show"                  => admin_user_path(users(:one)),
      "user edit"                  => edit_admin_user_path(users(:one)),
      "ban form"                   => new_admin_user_ban_path(users(:one)),
      "stores index"               => admin_stores_path,
      "store show"                 => admin_store_path(stores(:one)),
      "store edit"                 => edit_admin_store_path(stores(:one)),
      "orders index"               => admin_orders_path,
      "orders index filtered"      => admin_orders_path(status: "completed", q: "PCM"),
      "order show"                 => admin_order_path(orders(:one)),
      "disputes index"             => admin_disputes_path,
      "dispute show"               => admin_dispute_path(@disputed),
      "dispute resolution form"    => new_admin_dispute_resolution_path(@disputed),
      "reviews index"              => admin_reviews_path,
      "categories index"           => admin_categories_path,
      "category new"               => new_admin_category_path,
      "category edit"              => edit_admin_category_path(categories(:rtx)),
      "category spec attributes"   => admin_category_spec_attributes_path(categories(:gpus)),
      "spec attributes index"      => admin_spec_attributes_path,
      "spec attribute new"         => new_admin_spec_attribute_path,
      "spec attribute edit"        => edit_admin_spec_attribute_path(spec_attributes(:vram)),
      "labels index"               => admin_labels_path,
      "label new"                  => new_admin_label_path,
      "label edit"                 => edit_admin_label_path(labels(:open_box)),
      "seller tags index"          => admin_seller_tags_path,
      "seller tag new"             => new_admin_seller_tag_path,
      "seller tag edit"            => edit_admin_seller_tag_path(seller_tags(:watercooled)),
      "countries index"            => admin_countries_path,
      "country edit"               => edit_admin_country_path(countries(:es)),
      "feature flags"              => admin_feature_flags_path,
      "settings"                   => edit_admin_settings_path,
      "legal pages index"          => admin_legal_pages_path,
      "legal page show"            => admin_legal_page_path(@legal_page),
      "legal page new"             => new_admin_legal_page_path,
      "legal page copy form"       => new_admin_legal_page_path(country_code: "ES", locale: "en", slug: "terms"),
      "legal page edit"            => edit_admin_legal_page_path(@legal_page),
      "reports index"              => admin_reports_path,
      "report show"                => admin_report_path(@report),
      "contact messages index"     => admin_contact_messages_path,
      "contact message show"       => admin_contact_message_path(@contact_message),
      "newsletter index"           => admin_newsletter_subscriptions_path,
      "audit logs"                 => admin_audit_logs_path,
      "audit logs filtered"        => admin_audit_logs_path(subject_type: "Listing", event_action: "approve_listing")
    }
  end

  PAGE_NAMES = [
    "dashboard root", "dashboard", "global search", "moderation queue",
    "moderation cockpit", "listings index", "listings index filtered",
    "listing show", "listing edit", "rejection form", "users index", "user show",
    "user edit", "ban form", "stores index", "store show", "store edit",
    "orders index", "orders index filtered", "order show", "disputes index",
    "dispute show", "dispute resolution form", "reviews index",
    "categories index", "category new", "category edit",
    "category spec attributes", "spec attributes index", "spec attribute new",
    "spec attribute edit", "labels index", "label new", "label edit",
    "seller tags index", "seller tag new", "seller tag edit", "countries index",
    "country edit", "feature flags", "settings", "legal pages index",
    "legal page show", "legal page new", "legal page copy form",
    "legal page edit", "reports index", "report show",
    "contact messages index", "contact message show",
    "newsletter index", "audit logs", "audit logs filtered"
  ].freeze

  # Phase 6b (part 2) routes — also swept for the non-admin 404 guard.
  PHASE_6B_ROUTES = %w[
    orders_index orders_index_filtered order_show disputes_index dispute_show
    dispute_resolution_form reviews_index categories_index category_new category_edit
    category_spec_attributes spec_attributes_index spec_attribute_new spec_attribute_edit
    labels_index label_new label_edit seller_tags_index seller_tag_new seller_tag_edit
    countries_index country_edit feature_flags settings legal_pages_index
    legal_page_show legal_page_new legal_page_copy_form legal_page_edit
    reports_index report_show contact_messages_index contact_message_show
    newsletter_index audit_logs audit_logs_filtered
  ].freeze

  PAGE_NAMES.each do |page_name|
    define_method "test_renders_#{page_name.tr('/', '').gsub(' ', '_')}" do
      get admin_pages.fetch(page_name)
      assert_response :ok, "#{page_name.inspect} did not render OK"
      refute_match(/translation missing/, response.body, "#{page_name.inspect} contains untranslated text")
    end
  end

  test "page coverage list matches the route hash" do
    assert_equal PAGE_NAMES.sort, admin_pages.keys.sort
  end

  test "sidebar links every nav section" do
    get admin_dashboard_path

    Admin::SidebarHelper::ADMIN_NAV.each do |section, label_key, _icon|
      assert_includes response.body, I18n.t(label_key), "sidebar is missing the #{section} link"
    end
  end

  test "non-admin users get 404 on every Phase 6b admin page" do
    sign_in_as users(:two)

    pages = admin_pages
    slug = ->(name) { name.tr("/", "").gsub(" ", "_") }

    PHASE_6B_ROUTES.each do |key|
      page_name = pages.keys.find { |name| slug.call(name) == key }
      flunk "no admin page registered for #{key.inspect}" if page_name.nil?

      get pages.fetch(page_name)
      assert_response :not_found, "#{page_name.inspect} must 404 for a regular user"
    end
  end

  private

  def disputed_order
    Order.create!(number: "PCM-2025-999001", buyer: users(:one), seller: users(:two),
                  status: :disputed, subtotal_cents: 50_000, total_cents: 50_000,
                  paid_at: 3.days.ago)
  end

  def legal_page
    LegalPage.create!(country_code: "ES", locale: "en", slug: "terms",
                      title: "Terms", body: "## Terms\n\nPlain text.", published: true)
  end

  def open_report
    Report.create!(listing: listings(:gigabyte), user: users(:two),
                   reason: :prohibited, details: "Item looks banned.")
  end

  def contact_message
    ContactMessage.create!(name: "Marta García", email: "marta@example.com",
                           subject: "Problema con el pedido",
                           body: "No he recibido el pedido todavía.", locale: "es")
  end
end
