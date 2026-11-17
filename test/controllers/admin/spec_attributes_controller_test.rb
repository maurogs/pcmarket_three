require "test_helper"

class Admin::SpecAttributesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  # Rendering

  test "index lists attributes with their keys and names" do
    get admin_spec_attributes_path
    assert_response :success
    assert_select "td", text: "vram"
    assert_select "td", text: "VRAM"
    assert_select "td", text: "negotiable"
  end

  test "new renders the form" do
    get new_admin_spec_attribute_path
    assert_response :success
    assert_select "input[name='spec_attribute[key]']"
  end

  test "edit renders the attribute with its options" do
    get edit_admin_spec_attribute_path(spec_attributes(:vram))
    assert_response :success
    assert_match "8GB", response.body
    assert_match "12GB", response.body
  end

  # Create

  test "admin creates a spec attribute with per-locale names (audited)" do
    assert_difference %w[SpecAttribute.count AdminAuditLog.count] do
      post admin_spec_attributes_path, params: {
        spec_attribute: {
          key: "cooler", input_type: "select", position: "7", filterable: "1",
          names: { "en" => "Cooler", "es" => "Refrigerador" }
        }
      }
    end
    attribute = SpecAttribute.find_by!(key: "cooler")
    assert_redirected_to edit_admin_spec_attribute_path(attribute)
    assert_equal({ "en" => "Cooler", "es" => "Refrigerador" }, attribute.names)
    assert_equal "spec_attribute_create", AdminAuditLog.last.action
  end

  test "duplicate key is rejected" do
    assert_no_difference "SpecAttribute.count" do
      post admin_spec_attributes_path, params: {
        spec_attribute: { key: "vram", input_type: "select", position: "1",
                          names: { "en" => "Dup" } }
      }
    end
    assert_response :unprocessable_entity
  end

  test "blank key is rejected" do
    assert_no_difference "SpecAttribute.count" do
      post admin_spec_attributes_path, params: {
        spec_attribute: { key: "", input_type: "select", position: "1",
                          names: { "en" => "No key" } }
      }
    end
    assert_response :unprocessable_entity
  end

  # Update — names/position persist, key is frozen

  test "update persists names and position and keeps untouched locales" do
    attribute = spec_attributes(:vram) # fixture names: en "VRAM", es "VRAM"

    assert_difference "AdminAuditLog.count" do
      patch admin_spec_attribute_path(attribute), params: {
        spec_attribute: { position: "4", filterable: "0",
                          names: { "en" => "Video RAM" } }
      }
    end
    assert_redirected_to edit_admin_spec_attribute_path(attribute)
    attribute.reload
    assert_equal 4, attribute.position
    assert_not attribute.filterable?
    assert_equal "Video RAM", attribute.names["en"]
    assert_equal "VRAM", attribute.names["es"]
    assert_equal "spec_attribute_update", AdminAuditLog.last.action
  end

  test "key is immutable: a different key on update never changes it" do
    attribute = spec_attributes(:vram)

    patch admin_spec_attribute_path(attribute), params: {
      spec_attribute: { key: "memory", names: { "en" => "Video RAM" } }
    }

    attribute.reload
    assert_equal "vram", attribute.key
    assert_equal "Video RAM", attribute.names["en"]
  end

  test "key immutability is also enforced at the model level" do
    attribute = spec_attributes(:vram)
    assert_raises(ActiveRecord::RecordInvalid) { attribute.update!(key: "memory") }
    assert_equal "vram", attribute.reload.key
  end

  # Destroy — blocked while an option is in use, allowed when not

  test "destroy is blocked when one of its options is used by listings" do
    # vram's 8GB/12GB options are carried by the fixture listings.
    attribute = spec_attributes(:vram)

    assert_no_difference "SpecAttribute.count" do
      assert_difference "AdminAuditLog.count" do
        delete admin_spec_attribute_path(attribute)
      end
    end
    assert_not flash[:alert].blank?
    assert_equal "spec_attribute_delete_blocked", AdminAuditLog.last.action
    assert attribute.reload.persisted?
    assert_equal 2, attribute.spec_options.count
  end

  test "destroy removes an unused attribute" do
    attribute = SpecAttribute.create!(key: "throwaway", input_type: :text,
                                      position: 99, names: { "en" => "Throwaway" })

    assert_difference -> { SpecAttribute.count }, -1 do
      assert_difference "AdminAuditLog.count" do
        delete admin_spec_attribute_path(attribute)
      end
    end
    assert_redirected_to admin_spec_attributes_path
    assert_not flash[:notice].blank?
    assert_equal "spec_attribute_destroy", AdminAuditLog.last.action
  end

  # Access control

  test "non-admin gets 404 on every action" do
    sign_in_as users(:one)

    get admin_spec_attributes_path
    assert_response :not_found
    get new_admin_spec_attribute_path
    assert_response :not_found
    get edit_admin_spec_attribute_path(spec_attributes(:vram))
    assert_response :not_found
    post admin_spec_attributes_path, params: {
      spec_attribute: { key: "sneaky", names: { "en" => "Sneaky" } }
    }
    assert_response :not_found
    patch admin_spec_attribute_path(spec_attributes(:vram)), params: {
      spec_attribute: { position: "1" }
    }
    assert_response :not_found
    assert_no_difference "SpecAttribute.count" do
      delete admin_spec_attribute_path(spec_attributes(:vram))
    end
    assert_response :not_found
  end
end
