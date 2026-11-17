require "test_helper"

class Admin::SellerTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "index lists seller tags by translated name" do
    get admin_seller_tags_path
    assert_response :ok
    assert_includes response.body, "Watercooled"
    assert_includes response.body, "Silent build"
  end

  test "new and edit render" do
    get new_admin_seller_tag_path
    assert_response :ok

    get edit_admin_seller_tag_path(seller_tags(:watercooled))
    assert_response :ok
    assert_includes response.body, "Watercooled"
  end

  test "create persists the translated names and auto-generates the slug (audited)" do
    assert_difference %w[SellerTag.count AdminAuditLog.count] do
      post admin_seller_tags_path, params: {
        seller_tag: { names: { en: "Gaming ready", es: "Listo para jugar" } }
      }
    end
    assert_redirected_to admin_seller_tags_path

    tag = SellerTag.find_by(slug: "gaming-ready")
    assert_not_nil tag, "slug should be generated from the English name"
    assert_equal({ "en" => "Gaming ready", "es" => "Listo para jugar" }, tag.names)

    audit = AdminAuditLog.find_by(action: "seller_tag_create", subject: tag)
    assert_equal "gaming-ready", audit.details["slug"]
  end

  test "create with blank names is rejected with 422" do
    assert_no_difference "SellerTag.count" do
      post admin_seller_tags_path, params: { seller_tag: { names: { en: "", es: "" } } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the name without touching the slug" do
    tag = seller_tags(:silent_build)

    patch admin_seller_tag_path(tag), params: { seller_tag: { names: { en: "Ultra silent" } } }
    assert_redirected_to admin_seller_tags_path

    tag.reload
    assert_equal "Ultra silent", tag.names["en"]
    assert_equal "Montaje silencioso", tag.names["es"], "untouched locales are preserved"
    assert_equal "silent-build", tag.slug
    assert_equal 1, AdminAuditLog.where(action: "seller_tag_update", subject: tag).count
  end

  test "destroy removes an unused seller tag (audited)" do
    tag = SellerTag.create!(names: { "en" => "Spare tag" })

    assert_difference "AdminAuditLog.count" do
      assert_difference "SellerTag.count", -1 do
        delete admin_seller_tag_path(tag)
      end
    end
    assert_redirected_to admin_seller_tags_path
    assert_equal 1, AdminAuditLog.where(action: "seller_tag_destroy", subject_type: "SellerTag", subject_id: tag.id).count
  end

  # Implemented behaviour: deletion is NOT blocked while in use — it cascades
  # through listing_tags (has_many dependent: :destroy).
  test "destroy while attached to listings deletes the tag and its join rows" do
    tag = seller_tags(:watercooled)
    assert tag.listings.exists?
    join_count = ListingTag.where(seller_tag: tag).count
    assert_operator join_count, :>, 0

    assert_difference "ListingTag.where(seller_tag: tag).count", -join_count do
      assert_difference "SellerTag.count", -1 do
        delete admin_seller_tag_path(tag)
      end
    end
    assert_redirected_to admin_seller_tags_path
    assert_not SellerTag.exists?(tag.id)
  end

  test "non-admin gets 404 on every seller tag action" do
    sign_in_as users(:one)

    get admin_seller_tags_path
    assert_response :not_found
    get new_admin_seller_tag_path
    assert_response :not_found
    get edit_admin_seller_tag_path(seller_tags(:watercooled))
    assert_response :not_found
    assert_no_difference "SellerTag.count" do
      post admin_seller_tags_path, params: { seller_tag: { names: { en: "Sneaky" } } }
    end
    assert_response :not_found
    patch admin_seller_tag_path(seller_tags(:watercooled)), params: { seller_tag: { names: { en: "Sneaky" } } }
    assert_response :not_found
    assert_no_difference "SellerTag.count" do
      delete admin_seller_tag_path(seller_tags(:watercooled))
    end
    assert_response :not_found
  end
end
