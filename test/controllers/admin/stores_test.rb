require "test_helper"

class Admin::StoresTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists stores and filters verified ones" do
    stores(:one).update!(verified: true)

    get admin_stores_path(verified: "yes")
    assert_response :success
    assert_match stores(:one).name, response.body
    assert_no_match stores(:two).name, response.body
  end

  test "verifying and unverifying a store is audited" do
    store = stores(:two)

    post admin_store_verification_path(store)
    assert_response :redirect
    assert_predicate store.reload, :verified?
    assert_equal 1, AdminAuditLog.where(action: "verify_store", subject: store).count

    delete admin_store_verification_path(store)
    assert_response :redirect
    assert_not store.reload.verified?
    assert_equal 1, AdminAuditLog.where(action: "unverify_store", subject: store).count
  end

  test "hiding a store pulls it from the marketplace and back" do
    store = stores(:two)

    post admin_store_hiding_path(store)
    assert_response :redirect
    assert_predicate store.reload, :hidden?

    delete admin_store_hiding_path(store)
    assert_response :redirect
    assert_not store.reload.hidden?

    %w[hide_store unhide_store].each do |action|
      assert_equal 1, AdminAuditLog.where(action: action, subject: store).count
    end
  end

  test "hidden stores stay visible in the admin index" do
    stores(:two).update!(hidden: true)

    get admin_stores_path
    assert_response :success
    assert_match stores(:two).name, response.body
  end

  test "store edit updates the name" do
    patch admin_store_path(stores(:two)), params: { store: { name: "Renamed Store" } }
    assert_response :redirect
    assert_equal "Renamed Store", stores(:two).reload.name
    assert_equal 1, AdminAuditLog.where(action: "edit_store", subject: stores(:two)).count
  end
end
