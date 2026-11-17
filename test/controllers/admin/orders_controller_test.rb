require "test_helper"

# Admin order workspace (Phase 6b): read-only index/show with filters plus the
# audited forced status transition (`update`). The normal buyer/seller state
# machine is not involved here — that flow lives in the public area.
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @order = orders(:one) # completed, buyer one, seller two
  end

  test "index lists every order for an admin" do
    get admin_orders_path
    assert_response :success
    assert_match orders(:one).number, response.body
    assert_match orders(:two).number, response.body
  end

  test "index filters by status" do
    other = other_status_order # cancelled, PCM-2024-900101
    assert_not_equal "completed", other.status

    get admin_orders_path(status: "completed")
    assert_response :success
    assert_match orders(:one).number, response.body
    assert_match orders(:two).number, response.body
    assert_no_match other.number, response.body
  end

  test "index filters by order number" do
    other = other_status_order

    get admin_orders_path(q: "PCM-2025")
    assert_response :success
    assert_match orders(:one).number, response.body
    assert_match orders(:two).number, response.body
    assert_no_match other.number, response.body

    get admin_orders_path(q: orders(:two).number)
    assert_response :success
    assert_match orders(:two).number, response.body
    assert_no_match orders(:one).number, response.body
  end

  test "index filters by buyer e-mail" do
    get admin_orders_path(buyer: "one@example.com")
    assert_response :success
    assert_match orders(:one).number, response.body # buyer = one
    assert_no_match orders(:two).number, response.body # buyer = two
  end

  test "index filters by seller e-mail" do
    get admin_orders_path(seller: "two@example.com")
    assert_response :success
    assert_match orders(:one).number, response.body # seller = two
    assert_no_match orders(:two).number, response.body # seller = one
  end

  test "index ignores an unknown status value" do
    get admin_orders_path(status: "not_a_status")
    assert_response :success
    assert_match orders(:one).number, response.body
    assert_match orders(:two).number, response.body
  end

  test "show renders the order with the forced-transition form" do
    get admin_order_path(@order)
    assert_response :success
    assert_match @order.number, response.body
    assert_match @order.buyer.username, response.body
    assert_match I18n.t("admin.orders.show.transition_title"), response.body
  end

  test "forced transition ignores the state machine and is audited" do
    # completed -> shipped is impossible in the buyer/seller flow; the admin
    # override must still apply it, stamp the target timestamp and audit it.
    assert_predicate @order, :completed?

    assert_difference "AdminAuditLog.count" do
      assert_difference "Notification.count", 2 do
        patch admin_order_path(@order),
              params: { order: { status: "shipped", reason: "Reopening the shipment" },
                        from_status: "completed" }
      end
    end
    assert_response :redirect
    assert_redirected_to admin_order_path(@order)
    assert_equal I18n.t("admin.orders.update.updated", number: @order.number), flash[:notice]

    @order.reload
    assert_predicate @order, :shipped?
    assert_not_nil @order.shipped_at

    event = AdminAuditLog.last
    assert_equal "order_force_transition", event.action
    assert_equal users(:admin), event.admin
    assert_equal @order, event.subject
    assert_equal "completed", event.details["from"]
    assert_equal "shipped", event.details["to"]
    assert_equal "Reopening the shipment", event.details["reason"]

    follow_redirect!
    assert_response :success
    assert_match "order_force_transition", response.body
  end

  test "forced transition notifies buyer and seller" do
    assert_difference "Notification.count", 2 do
      patch admin_order_path(@order),
            params: { order: { status: "cancelled", reason: "Lost in transit" },
                      from_status: "completed" }
    end
    assert_response :redirect

    kinds = Notification.pluck(:user_id, :kind).to_h
    assert_equal "order_updated", kinds[users(:one).id]
    assert_equal "order_updated", kinds[users(:two).id]
  end

  test "forced transition without a reason is refused and unaudited" do
    assert_no_difference "AdminAuditLog.count" do
      patch admin_order_path(@order), params: { order: { status: "shipped", reason: "" } }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("admin.orders.update.errors.reason_missing"), flash[:alert]
    assert_match I18n.t("admin.orders.update.errors.reason_missing"), response.body
    assert_predicate @order.reload, :completed?
  end

  test "forced transition to an unknown status is refused" do
    assert_no_difference "AdminAuditLog.count" do
      patch admin_order_path(@order),
            params: { order: { status: "teleported", reason: "because" } }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("admin.orders.update.errors.invalid_status"), flash[:alert]
    assert_predicate @order.reload, :completed?
  end

  test "forced transition to the current status is refused as stale" do
    assert_no_difference "AdminAuditLog.count" do
      patch admin_order_path(@order),
            params: { order: { status: "completed", reason: "no change" } }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("admin.orders.update.errors.stale"), flash[:alert]
    assert_predicate @order.reload, :completed?
  end

  test "non-admin gets 404 on index, show and the transition" do
    sign_in_as users(:two)

    get admin_orders_path
    assert_response :not_found

    get admin_order_path(@order)
    assert_response :not_found

    assert_no_difference "AdminAuditLog.count" do
      patch admin_order_path(@order),
            params: { order: { status: "cancelled", reason: "sneaky" } }
    end
    assert_response :not_found
    assert_predicate @order.reload, :completed?
  end

  private

  # Extra order used by the index filters: never a fixture number, never
  # PCM-2026-*, so the other admin tests' data stays untouched.
  def other_status_order
    @other_status_order ||= Order.create!(number: "PCM-2024-900101", buyer: users(:one),
                                          seller: users(:two), status: :cancelled,
                                          subtotal_cents: 10_000)
  end
end
