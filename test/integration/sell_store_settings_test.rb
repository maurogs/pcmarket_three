require "test_helper"

class Sell::StoreSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @store = stores(:one)
    sign_in_as users(:one)
  end

  def patch_store(store_overrides = {})
    patch sell_store_path, params: {
      store: {
        name: "Refreshed Store",
        description: "Parts, upgrades and repairs.",
        store_type: "individual",
        city: "Madrid",
        region: "Madrid",
        default_shipping: "4.50",
        free_shipping_threshold: "150",
        shipping_policy: "24h dispatch.",
        returns_policy: "14 calendar days."
      }.merge(store_overrides)
    }
  end

  test "edit renders the settings form with current values" do
    get edit_sell_store_path
    assert_response :success
    assert_match "One Store", response.body
    assert_select "input[name='store[name]'][value='One Store']"
  end

  test "valid update saves text fields and euro money fields" do
    patch_store
    assert_redirected_to edit_sell_store_path
    @store.reload

    assert_equal "Refreshed Store", @store.name
    assert_equal 450, @store.default_shipping_cents
    assert_equal 15000, @store.free_shipping_threshold_cents
    assert_equal "24h dispatch.", @store.shipping_policy
    assert_equal I18n.t("sell.stores.update.updated"), flash[:notice]
  end

  test "business store without a VAT number is rejected" do
    patch_store(store_type: "business")
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /VAT number can't be blank/
  end

  test "business store needs a valid Spanish tax ID" do
    patch_store(store_type: "business", vat_number: "12345678A")
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.messages.spanish_tax_id_invalid"), response.body

    patch_store(store_type: "business", vat_number: "G02377372")
    assert_redirected_to edit_sell_store_path
    assert_equal "G02377372", @store.reload.vat_number
  end

  test "oversized logo uploads are rejected" do
    file = Tempfile.new([ "big", ".png" ])
    file.write("x" * 6.megabytes)
    file.rewind

    patch sell_store_path, params: {
      store: { name: "One Store" },
      "store[logo]": Rack::Test::UploadedFile.new(file.path, "image/png")
    }
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.messages.logo_too_large", max: 5), response.body
  ensure
    file.close!
  end

  test "renaming the store 301-redirects the old public slug" do
    # Fixture inserts bypass FriendlyId's after_save, so seed the history row
    # a real (model-created) store would have for its original slug.
    @store.slugs.create!(slug: @store.slug)
    old_path = store_path(@store)
    get old_path
    assert_response :success

    patch_store
    new_slug = @store.reload.slug
    assert_not_equal "one-store", new_slug

    get old_path
    assert_response :moved_permanently
    assert_equal store_url(@store), response.location
    follow_redirect!
    assert_response :success
    assert_match "Refreshed Store", response.body
  end

  test "invalid euro strings keep the form dirty instead of saving" do
    patch_store(default_shipping: "not money")
    assert_response :unprocessable_entity
    assert_not_equal 450, stores(:one).reload.default_shipping_cents
  end
end
