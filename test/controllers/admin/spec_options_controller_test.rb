require "test_helper"

class Admin::SpecOptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @attribute = spec_attributes(:vram)
  end

  # Inline create / update / destroy

  test "admin creates an option inline with value and per-locale names (audited)" do
    assert_difference %w[SpecOption.count AdminAuditLog.count] do
      post admin_spec_attribute_spec_options_path(@attribute), params: {
        spec_option: { value: "16gb", position: "3",
                       names: { "en" => "16 GB", "es" => "16 GB" } }
      }
    end
    option = @attribute.spec_options.find_by!(value: "16gb")
    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    assert_equal({ "en" => "16 GB", "es" => "16 GB" }, option.names)
    assert_equal 3, option.position
    assert_equal "spec_option_create", AdminAuditLog.last.action
  end

  test "blank option value is rejected" do
    assert_no_difference "SpecOption.count" do
      post admin_spec_attribute_spec_options_path(@attribute), params: {
        spec_option: { value: "", names: { "en" => "Nothing" } }
      }
    end
    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    assert_not flash[:alert].blank?
  end

  test "update persists position, popular and names but never the value" do
    option = @attribute.spec_options.create!(value: "4gb", position: 9,
                                             names: { "en" => "4 GB", "es" => "4 GB" })

    assert_difference "AdminAuditLog.count" do
      patch admin_spec_attribute_spec_option_path(@attribute, option), params: {
        spec_option: { position: "2", popular: "1", value: "hacked",
                       names: { "es" => "4 gigabytes" } }
      }
    end
    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    option.reload
    assert_equal 2, option.position
    assert option.popular?
    assert_equal "4gb", option.value
    assert_equal "4 GB", option.names["en"]
    assert_equal "4 gigabytes", option.names["es"]
    assert_equal "spec_option_update", AdminAuditLog.last.action
  end

  test "destroy removes an unused option" do
    option = @attribute.spec_options.create!(value: "throwaway", position: 9,
                                             names: { "en" => "Throwaway" })

    assert_difference -> { SpecOption.count }, -1 do
      assert_difference "AdminAuditLog.count" do
        delete admin_spec_attribute_spec_option_path(@attribute, option)
      end
    end
    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    assert_not flash[:notice].blank?
    assert_equal "spec_option_destroy", AdminAuditLog.last.action
  end

  test "destroy is blocked while listings use the option" do
    # The fixture listings carry hdmi in their ports arrays.
    option = spec_options(:hdmi)
    assert_operator option.listings_using_count, :positive?

    assert_no_difference "SpecOption.count" do
      assert_difference "AdminAuditLog.count" do
        delete admin_spec_attribute_spec_option_path(spec_attributes(:ports), option)
      end
    end
    assert_redirected_to edit_admin_spec_attribute_path(spec_attributes(:ports))
    assert_not flash[:alert].blank?
    assert_equal "spec_option_delete_blocked", AdminAuditLog.last.action
    assert option.reload.persisted?
  end

  # Bulk add

  test "bulk add creates one option per line, skipping duplicates and junk" do
    attribute = SpecAttribute.create!(key: "cooling", input_type: :select,
                                      position: 50, names: { "en" => "Cooling" })
    attribute.spec_options.create!(value: "air", position: 7, names: { "en" => "Air" })

    assert_difference -> { SpecOption.count }, 2 do
      assert_difference "AdminAuditLog.count" do
        post admin_spec_attribute_bulk_option_path(attribute), params: {
          bulk_option: { values: "Liquid\nLiquid\nLiquid CPU\nAir\n???\n" }
        }
      end
    end
    assert_redirected_to edit_admin_spec_attribute_path(attribute)
    assert_not flash[:notice].blank?

    liquid = attribute.spec_options.find_by!(value: "liquid")
    liquid_cpu = attribute.spec_options.find_by!(value: "liquid-cpu")
    assert_equal({ "en" => "Liquid" }, liquid.names)
    assert_equal({ "en" => "Liquid CPU" }, liquid_cpu.names)
    assert_equal [ 8, 9 ], [ liquid.position, liquid_cpu.position ]

    audit = AdminAuditLog.last
    assert_equal "spec_option_bulk_create", audit.action
    assert_equal %w[liquid liquid-cpu], audit.details["created"]
    assert_equal [ "Air", "???" ], audit.details["skipped"]
  end

  # Merge

  test "merge rewrites referencing listings and destroys the source option" do
    # gigabyte and featured carry vram: 12GB in their specs jsonb.
    assert_equal "12GB", listings(:gigabyte).reload.specs["vram"]
    assert_equal 2, Listing.using_spec_value("vram", "12GB").count
    assert_equal 3, Listing.using_spec_value("vram", "8GB").count

    post admin_spec_attribute_spec_option_merge_path(@attribute, spec_options(:vram_12)),
         params: { merge: { target_id: spec_options(:vram_8).id } }

    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    assert_not flash[:notice].blank?
    assert_not SpecOption.exists?(spec_options(:vram_12).id)
    assert_equal 0, Listing.using_spec_value("vram", "12GB").count
    assert_equal 5, Listing.using_spec_value("vram", "8GB").count
    assert_equal "8GB", listings(:gigabyte).reload.specs["vram"]
    assert_equal "8GB", listings(:featured).reload.specs["vram"]

    audit = AdminAuditLog.last
    assert_equal "spec_option_merge", audit.action
    assert_equal 2, audit.details["listings_rewritten"]
  end

  test "merge rewrites every referencing listing with a single UPDATE" do
    update_statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, _name, payload|
      update_statements << payload[:sql] if payload[:sql].match?(/\AUPDATE listings\b/)
    end

    begin
      SpecOptions::Merge.call(option: spec_options(:vram_12), target: spec_options(:vram_8))
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal 1, update_statements.size
    assert_match "jsonb_set", update_statements.first
    assert_equal 0, Listing.using_spec_value("vram", "12GB").count
    assert_not SpecOption.exists?(spec_options(:vram_12).id)
  end

  test "merging an option into itself is rejected" do
    assert_no_difference "SpecOption.count" do
      post admin_spec_attribute_spec_option_merge_path(@attribute, spec_options(:vram_12)),
           params: { merge: { target_id: spec_options(:vram_12).id } }
    end
    assert_redirected_to edit_admin_spec_attribute_path(@attribute)
    assert_not flash[:alert].blank?
    assert spec_options(:vram_12).reload.persisted?
  end

  # Access control

  test "non-admin gets 404 on every option action" do
    sign_in_as users(:one)
    option = spec_options(:vram_8)

    post admin_spec_attribute_spec_options_path(@attribute), params: {
      spec_option: { value: "sneaky", names: { "en" => "Sneaky" } }
    }
    assert_response :not_found
    patch admin_spec_attribute_spec_option_path(@attribute, option), params: {
      spec_option: { position: "1" }
    }
    assert_response :not_found
    assert_no_difference "SpecOption.count" do
      delete admin_spec_attribute_spec_option_path(@attribute, option)
    end
    assert_response :not_found
    assert_no_difference "SpecOption.count" do
      post admin_spec_attribute_spec_option_merge_path(@attribute, option),
           params: { merge: { target_id: spec_options(:vram_12).id } }
    end
    assert_response :not_found
    post admin_spec_attribute_bulk_option_path(@attribute), params: {
      bulk_option: { values: "sneaky" }
    }
    assert_response :not_found
  end
end
