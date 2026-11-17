require "test_helper"

class Admin::CategorySpecAttributesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @category = categories(:gpus)
  end

  test "index lists the attached attributes" do
    get admin_category_spec_attributes_path(@category)
    assert_response :success
    assert_select "span", text: "VRAM"
    assert_select "span", text: "Negotiable"
    assert_select "span", text: "Ports"
  end

  test "admin attaches an unattached spec attribute (audited)" do
    attribute = SpecAttribute.create!(key: "cooling", input_type: :select,
                                      position: 50, names: { "en" => "Cooling" })

    assert_difference %w[CategorySpecAttribute.count AdminAuditLog.count] do
      post admin_category_spec_attributes_path(@category), params: {
        category_spec_attribute: { spec_attribute_id: attribute.id, required: "0" }
      }
    end
    row = @category.category_spec_attributes.find_by!(spec_attribute: attribute)
    assert_redirected_to admin_category_spec_attributes_path(@category)
    assert_not row.required?

    audit = AdminAuditLog.last
    assert_equal "category_spec_attribute_attach", audit.action
    assert_equal "cooling", audit.details["spec_key"]
  end

  test "attaching an already attached attribute is rejected" do
    assert_no_difference "CategorySpecAttribute.count" do
      post admin_category_spec_attributes_path(@category), params: {
        category_spec_attribute: { spec_attribute_id: spec_attributes(:vram).id }
      }
    end
    assert_redirected_to admin_category_spec_attributes_path(@category)
    assert_not flash[:alert].blank?
  end

  test "update toggles the required flag on the join row" do
    row = category_spec_attributes(:vram_gpus)
    assert_not row.required?

    assert_difference "AdminAuditLog.count" do
      patch admin_category_spec_attribute_path(@category, row), params: {
        category_spec_attribute: { required: "1", position: row.position }
      }
    end
    assert_redirected_to admin_category_spec_attributes_path(@category)
    assert row.reload.required?

    patch admin_category_spec_attribute_path(@category, row), params: {
      category_spec_attribute: { required: "0", position: row.position }
    }
    assert_not row.reload.required?
    assert_equal "category_spec_attribute_update", AdminAuditLog.last.action
  end

  test "destroy detaches the attribute but keeps the attribute itself" do
    row = category_spec_attributes(:ports_gpus)

    assert_difference -> { CategorySpecAttribute.count }, -1 do
      assert_difference "AdminAuditLog.count" do
        delete admin_category_spec_attribute_path(@category, row)
      end
    end
    assert_redirected_to admin_category_spec_attributes_path(@category)
    assert SpecAttribute.exists?(spec_attributes(:ports).id)
    assert_equal "category_spec_attribute_detach", AdminAuditLog.last.action
  end

  test "non-admin gets 404 on every action" do
    sign_in_as users(:one)

    get admin_category_spec_attributes_path(@category)
    assert_response :not_found
    assert_no_difference "CategorySpecAttribute.count" do
      post admin_category_spec_attributes_path(@category), params: {
        category_spec_attribute: { spec_attribute_id: spec_attributes(:vram).id }
      }
    end
    assert_response :not_found
    patch admin_category_spec_attribute_path(@category, category_spec_attributes(:vram_gpus)),
         params: { category_spec_attribute: { required: "1" } }
    assert_response :not_found
    assert_no_difference "CategorySpecAttribute.count" do
      delete admin_category_spec_attribute_path(@category, category_spec_attributes(:vram_gpus))
    end
    assert_response :not_found
  end
end
