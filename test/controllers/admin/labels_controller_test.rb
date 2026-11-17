require "test_helper"

class Admin::LabelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "index lists labels by translated name" do
    get admin_labels_path
    assert_response :ok
    assert_includes response.body, "Open box"
    assert_includes response.body, "Local pickup only"
  end

  test "new and edit render" do
    get new_admin_label_path
    assert_response :ok

    get edit_admin_label_path(labels(:open_box))
    assert_response :ok
    assert_includes response.body, "Open box"
  end

  test "create persists the translated names and auto-generates the slug (audited)" do
    assert_difference %w[Label.count AdminAuditLog.count] do
      post admin_labels_path, params: {
        label: { names: { en: "Brand new", es: "Nuevo de marca" }, color: "#3b82f6" }
      }
    end
    assert_redirected_to admin_labels_path

    label = Label.find_by(slug: "brand-new")
    assert_not_nil label, "slug should be generated from the English name"
    assert_equal({ "en" => "Brand new", "es" => "Nuevo de marca" }, label.names)
    assert_equal "#3b82f6", label.color

    audit = AdminAuditLog.find_by(action: "label_create", subject: label)
    assert_equal "brand-new", audit.details["slug"]
  end

  test "create with blank names is rejected with 422" do
    assert_no_difference "Label.count" do
      post admin_labels_path, params: { label: { names: { en: "", es: "" }, color: "#3b82f6" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with an invalid color is rejected with 422" do
    assert_no_difference "Label.count" do
      post admin_labels_path, params: { label: { names: { en: "Naughty color" }, color: "blue" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the name and color without touching the slug" do
    label = labels(:local_pickup_only)

    patch admin_label_path(label), params: {
      label: { names: { es: "Solo recogida" }, color: "#f59e0b" }
    }
    assert_redirected_to admin_labels_path

    label.reload
    assert_equal "Solo recogida", label.names["es"]
    assert_equal "Local pickup only", label.names["en"], "untouched locales are preserved"
    assert_equal "#f59e0b", label.color
    assert_equal "local-pickup-only", label.slug
    assert_equal 1, AdminAuditLog.where(action: "label_update", subject: label).count
  end

  test "destroy removes an unused label (audited)" do
    label = Label.create!(names: { "en" => "Spare label" })

    assert_difference "AdminAuditLog.count" do
      assert_difference "Label.count", -1 do
        delete admin_label_path(label)
      end
    end
    assert_redirected_to admin_labels_path
    assert_equal 1, AdminAuditLog.where(action: "label_destroy", subject_type: "Label", subject_id: label.id).count
  end

  # Implemented behaviour: deletion is NOT blocked while in use — it cascades
  # through listing_labels (has_many dependent: :destroy).
  test "destroy while attached to listings deletes the label and its join rows" do
    label = labels(:open_box)
    assert label.listings.exists?

    assert_difference "ListingLabel.where(label: label).count", -ListingLabel.where(label: label).count do
      assert_difference "Label.count", -1 do
        delete admin_label_path(label)
      end
    end
    assert_redirected_to admin_labels_path
    assert_not Label.exists?(label.id)
  end

  test "non-admin gets 404 on every label action" do
    sign_in_as users(:one)

    get admin_labels_path
    assert_response :not_found
    get new_admin_label_path
    assert_response :not_found
    get edit_admin_label_path(labels(:open_box))
    assert_response :not_found
    assert_no_difference "Label.count" do
      post admin_labels_path, params: { label: { names: { en: "Sneaky" } } }
    end
    assert_response :not_found
    patch admin_label_path(labels(:open_box)), params: { label: { names: { en: "Sneaky" } } }
    assert_response :not_found
    assert_no_difference "Label.count" do
      delete admin_label_path(labels(:open_box))
    end
    assert_response :not_found
  end
end
