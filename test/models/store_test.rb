require "test_helper"

class StoreTest < ActiveSupport::TestCase
  def build_store(name, **attrs)
    Store.new(user: users(:one), name: name, store_type: :individual, **attrs)
  end

  test "name must be unique and between 2 and 60 characters" do
    duplicate = build_store("One Store")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_not build_store("A").valid?
    assert_not build_store("A" * 61).valid?
    assert build_store("Valid name #{SecureRandom.hex(4)}").valid?
  end

  test "description is capped at 2000 characters" do
    store = build_store("Desc #{SecureRandom.hex(4)}", description: "x" * 2001)
    assert_not store.valid?
    assert_includes store.errors[:description], "is too long (maximum is 2000 characters)"
  end

  test "business stores require a valid Spanish tax ID" do
    no_vat = build_store("Biz #{SecureRandom.hex(4)}", store_type: :business)
    assert_not no_vat.valid?
    assert_includes no_vat.errors[:vat_number], "can't be blank"

    bad_vat = build_store("Biz #{SecureRandom.hex(4)}", store_type: :business, vat_number: "12345678A")
    assert_not bad_vat.valid?
    assert_includes bad_vat.errors[:vat_number], I18n.t("activerecord.errors.messages.spanish_tax_id_invalid")

    good = build_store("Biz #{SecureRandom.hex(4)}", store_type: :business, vat_number: "G02377372")
    assert good.valid?, good.errors.full_messages.join(", ")
  end

  test "individual stores may omit the VAT number" do
    store = build_store("Person #{SecureRandom.hex(4)}")
    assert store.vat_number.blank?
    assert store.valid?, store.errors.full_messages.join(", ")
  end

  test "region must be a known Spanish province" do
    store = build_store("Prov #{SecureRandom.hex(4)}", region: "Atlantis")
    assert_not store.valid?
    assert_includes store.errors[:region], I18n.t("activerecord.errors.messages.province_unknown")

    ok = build_store("Prov #{SecureRandom.hex(4)}", region: "A Coruña")
    assert ok.valid?, ok.errors.full_messages.join(", ")
  end

  test "logo must be an image within the size limit" do
    store = build_store("Logo #{SecureRandom.hex(4)}")
    store.logo.attach(io: StringIO.new("plain"), filename: "logo.txt", content_type: "text/plain")
    assert_not store.valid?
    assert_includes store.errors[:logo], I18n.t("activerecord.errors.messages.logo_content_type_invalid")

    other = build_store("Logo2 #{SecureRandom.hex(4)}")
    other.logo.attach(io: StringIO.new("x" * 6.megabytes), filename: "big.png", content_type: "image/png")
    assert_not other.valid?
    assert_includes other.errors[:logo], I18n.t("activerecord.errors.messages.logo_too_large", max: 5)
  end

  test "banner must respect the 8 MB cap" do
    store = build_store("Banner #{SecureRandom.hex(4)}")
    store.banner.attach(io: StringIO.new("x" * 9.megabytes), filename: "wide.png", content_type: "image/png")
    assert_not store.valid?
    assert_includes store.errors[:banner], I18n.t("activerecord.errors.messages.banner_too_large", max: 8)
  end

  test "renaming regenerates the slug and keeps old slugs resolvable" do
    # Fixtures bypass FriendlyId's after_save, so fixture stores have no
    # history rows — create through the model to exercise slug lifecycle.
    store = Store.create!(user: users(:admin), name: "Rename Probe #{SecureRandom.hex(4)}",
                          store_type: :individual)
    old_slug = store.slug

    store.update!(name: "Renamed Probe #{SecureRandom.hex(4)}")

    assert_not_equal old_slug, store.slug
    assert_includes store.slugs.pluck(:slug), old_slug
    assert_equal store.id, Store.friendly.find(old_slug).id
  end

  test "vacation mode toggles" do
    store = stores(:one)
    store.enable_vacation!
    assert store.reload.vacation_mode?

    store.disable_vacation!
    assert_not store.reload.vacation_mode?
  end
end
