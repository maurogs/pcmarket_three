require "test_helper"

class Admin::AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists audit rows written by admin actions" do
    assert_difference -> { AdminAuditLog.count }, 1 do
      post admin_order_notes_path(orders(:one)), params: { order_note: { body: "Checked with the buyer." } }
    end
    log = AdminAuditLog.sole

    get admin_audit_logs_path
    assert_response :success
    assert_match log.action, response.body
    assert_match "OrderNote ##{log.subject_id}", response.body
    assert_match users(:admin).display_name, response.body
  end

  test "subject_type filter narrows to that subject type" do
    note_log = audit_order_note
    legal_log = audit_legal_page

    get admin_audit_logs_path(subject_type: "OrderNote")
    assert_response :success
    assert_includes response.body, "OrderNote ##{note_log.subject_id}"
    assert_not_includes response.body, "LegalPage ##{legal_log.subject_id}"

    get admin_audit_logs_path(subject_type: "LegalPage")
    assert_response :success
    assert_includes response.body, "LegalPage ##{legal_log.subject_id}"
    assert_not_includes response.body, "OrderNote ##{note_log.subject_id}"
  end

  test "event_action filter narrows to that action" do
    note_log = audit_order_note
    legal_log = audit_legal_page

    get admin_audit_logs_path(event_action: "order_note_create")
    assert_response :success
    assert_includes response.body, "OrderNote ##{note_log.subject_id}"
    assert_not_includes response.body, "LegalPage ##{legal_log.subject_id}"

    get admin_audit_logs_path(event_action: "legal_page_create")
    assert_response :success
    assert_includes response.body, "LegalPage ##{legal_log.subject_id}"
    assert_not_includes response.body, "OrderNote ##{note_log.subject_id}"
  end

  test "unknown filter values are ignored, not applied blindly" do
    note_log = audit_order_note
    get admin_audit_logs_path(subject_type: "DropTable", event_action: "drop --", from: "garbage")
    assert_response :success
    assert_includes response.body, "OrderNote ##{note_log.subject_id}"
  end

  test "non-admin gets 404" do
    sign_in_as users(:one)
    get admin_audit_logs_path
    assert_response :not_found
  end

  private

  def audit_order_note
    post admin_order_notes_path(orders(:one)), params: { order_note: { body: "Note for audit test." } }
    AdminAuditLog.where(action: "order_note_create").order(:id).last
  end

  def audit_legal_page
    post admin_legal_pages_path, params: {
      legal_page: { country_code: "ES", locale: "en", slug: "cookies",
                    title: "Cookies Policy", body: "We use cookies.", published: "1" }
    }
    AdminAuditLog.where(action: "legal_page_create").order(:id).last
  end
end
