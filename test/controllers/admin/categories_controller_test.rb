require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "index shows the category tree with translated names" do
    get admin_categories_path
    assert_response :ok
    assert_includes response.body, "Graphics Cards"
    assert_includes response.body, "RTX Series"
  end

  test "new renders the form" do
    get new_admin_category_path
    assert_response :ok
  end

  test "edit renders the form for a fixture category" do
    get edit_admin_category_path(categories(:rtx))
    assert_response :ok
    assert_includes response.body, "Serie RTX"
  end

  test "create stores translated names and auto-generates the slug (audited)" do
    assert_difference %w[Category.count AdminAuditLog.count] do
      post admin_categories_path, params: {
        category: {
          names: { en: "Keyboards", es: "Teclados" },
          seo_descriptions: { en: "All keyboards" },
          icon: "keyboard", active: "1"
        }
      }
    end
    assert_redirected_to admin_categories_path

    category = Category.find_by(slug: "keyboards")
    assert_not_nil category, "slug should be generated from the name"
    assert_equal({ "en" => "Keyboards", "es" => "Teclados" }, category.names)
    assert_equal "All keyboards", category.seo_description
    assert_predicate category, :active?
    assert_nil category.parent_id

    audit = AdminAuditLog.find_by(action: "category_create", subject: category)
    assert_equal "keyboards", audit.details["slug"]
  end

  test "create with blank names re-renders 422 and stores nothing" do
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { names: { en: "", es: "" } } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes names and can archive with active=false" do
    category = categories(:rtx)

    patch admin_category_path(category), params: {
      category: { names: { en: "RTX 50 Series" }, active: "0", icon: "chip" }
    }
    assert_redirected_to admin_categories_path

    category.reload
    assert_equal "RTX 50 Series", category.names["en"]
    assert_equal "Serie RTX", category.names["es"], "untouched locales are preserved"
    assert_not_predicate category, :active?
    assert_equal "chip", category.icon

    audit = AdminAuditLog.find_by(action: "category_update", subject: category)
    assert_equal false, audit.details["active"]
    assert_equal category.slug, audit.details["slug"]
  end

  test "position up/down swaps positions between adjacent siblings" do
    first = Category.create!(slug: "pos-test-a", names: { "en" => "Pos Test A" }, position: 7)
    second = Category.create!(slug: "pos-test-b", names: { "en" => "Pos Test B" }, position: 8)

    post admin_category_position_path(first), params: { direction: "down" }
    assert_redirected_to admin_categories_path
    assert_equal 8, first.reload.position
    assert_equal 7, second.reload.position
    assert_equal 1, AdminAuditLog.where(action: "category_move", subject: first).count

    post admin_category_position_path(second), params: { direction: "down" }
    assert_redirected_to admin_categories_path
    assert_equal 7, first.reload.position
    assert_equal 8, second.reload.position
  end

  test "position at the edge of the level is refused with an alert" do
    top = Category.create!(slug: "pos-test-top", names: { "en" => "Pos Test Top" }, position: -5)
    gpus = categories(:gpus)

    post admin_category_position_path(top), params: { direction: "up" }
    assert_redirected_to admin_categories_path
    assert_not flash[:alert].blank?
    assert_equal(-5, top.reload.position)
    assert_equal 1, gpus.reload.position
    assert_equal 0, AdminAuditLog.where(action: "category_move", subject: top).count
  end

  test "position with an unknown direction is refused without crashing" do
    first = Category.create!(slug: "pos-test-bad", names: { "en" => "Pos Test Bad" }, position: 7)
    second = Category.create!(slug: "pos-test-bad-b", names: { "en" => "Pos Test Bad B" }, position: 8)

    assert_no_difference "AdminAuditLog.count" do
      post admin_category_position_path(first), params: { direction: "sideways" }
    end
    assert_redirected_to admin_categories_path
    assert_not flash[:alert].blank?
    assert_equal 7, first.reload.position
    assert_equal 8, second.reload.position
  end

  test "non-admin gets 404 on every category action" do
    sign_in_as users(:one)

    get admin_categories_path
    assert_response :not_found
    get new_admin_category_path
    assert_response :not_found
    get edit_admin_category_path(categories(:gpus))
    assert_response :not_found
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { names: { en: "Sneaky" } } }
    end
    assert_response :not_found
    patch admin_category_path(categories(:gpus)), params: { category: { names: { en: "Sneaky" } } }
    assert_response :not_found
    post admin_category_position_path(categories(:gpus)), params: { direction: "up" }
    assert_response :not_found
  end
end
