require "test_helper"

class Admin::NotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @order = orders(:one)
  end

  test "admin creates an order note (audited)" do
    assert_difference %w[OrderNote.count AdminAuditLog.count] do
      post admin_order_notes_path(@order), params: { order_note: { body: "Called the buyer." } }
    end
    assert_redirected_to admin_order_path(@order)
    note = OrderNote.last
    assert_equal "Called the buyer.", note.body
    assert_equal users(:admin), note.admin
    assert_equal "order_note_create", AdminAuditLog.last.action
  end

  test "blank note is rejected" do
    assert_no_difference "OrderNote.count" do
      post admin_order_notes_path(@order), params: { order_note: { body: "" } }
    end
    assert_redirected_to admin_order_path(@order)
    assert_not flash[:alert].blank?
  end

  test "non-admin gets 404" do
    sign_in_as users(:one)
    assert_no_difference "OrderNote.count" do
      post admin_order_notes_path(@order), params: { order_note: { body: "sneaky" } }
    end
    assert_response :not_found
  end
end
