require "test_helper"

class Admin::ModerationsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @pending = listings(:pending)
  end

  test "queue lists pending listings oldest first" do
    duplicate = duplicate_pending("Another queue item")

    get admin_moderations_path
    assert_response :success
    assert_select "table.admin-table"
    assert_match @pending.title, response.body
    assert_match duplicate.title, response.body
  end

  test "show renders the moderation cockpit" do
    get admin_moderation_path(@pending)
    assert_response :success
    assert_select "[data-controller~='moderation']"
    assert_match @pending.title, response.body
  end

  test "approving notifies the seller, audits and mails" do
    assert_difference [ -> { Notification.count }, -> { ModerationEvent.count },
                        -> { AdminAuditLog.count } ], 1 do
      assert_enqueued_emails 1 do
        post admin_listing_approval_path(@pending)
      end
    end

    assert_equal "approved", @pending.reload.status
    assert_not_nil @pending.published_at

    note = Notification.order(:id).last
    assert_equal users(:one), note.user
    assert_equal "listing_approved", note.kind

    log = AdminAuditLog.order(:id).last
    assert_equal users(:admin), log.admin
    assert_equal "approve_listing", log.action
    assert_equal @pending, log.subject

    follow_redirect!
    assert_match I18n.t("admin.approvals.create.approved", title: @pending.title), flash[:notice]
  end

  test "approving an already-reviewed listing is refused with an alert" do
    assert_no_difference [ -> { ModerationEvent.count } ] do
      post admin_listing_approval_path(listings(:gigabyte))
    end

    follow_redirect!
    assert_response :success
    assert_not_nil flash[:alert]
  end

  test "rejecting stores translated reason plus moderator note" do
    assert_difference [ -> { ModerationEvent.count }, -> { AdminAuditLog.count } ], 1 do
      assert_enqueued_emails 1 do
        post admin_listing_rejection_path(@pending),
             params: { reason: "blurry_photos", note: "Retake the third photo" }
      end
    end

    @pending.reload
    assert_equal "rejected", @pending.status
    label = I18n.t("admin.rejections.reasons.blurry_photos")
    assert_equal "#{label} — Retake the third photo", @pending.rejection_reason

    assert_includes AdminAuditLog.order(:id).last.details["reason"], "blurry_photos"

    follow_redirect!
    assert_match I18n.t("admin.rejections.create.rejected", title: @pending.title), flash[:notice]
  end

  test "rejecting without a reason re-renders the form" do
    assert_no_difference [ -> { ModerationEvent.count } ] do
      post admin_listing_rejection_path(@pending), params: { reason: "" }
      assert_response :unprocessable_entity
      assert_match I18n.t("admin.rejections.create.reason_required"), response.body
    end
  end

  test "rejecting with an unknown reason key is refused" do
    assert_no_difference [ -> { ModerationEvent.count } ] do
      post admin_listing_rejection_path(@pending), params: { reason_key: "i-dont-like-it" }
      assert_response :unprocessable_entity
    end
  end

  test "bulk approve processes the selection and logs once" do
    a = duplicate_pending("Bulk one")
    b = duplicate_pending("Bulk two")
    already = listings(:gigabyte) # approved already -> counted as skipped

    assert_difference [ -> { Notification.count } ], 2 do
      assert_difference -> { AdminAuditLog.count }, 1 do
        post admin_bulk_moderation_path,
             params: { decision: "approve", listing_ids: [ a.id, b.id, already.id ] }
      end
    end

    assert_predicate a.reload, :approved?
    assert_predicate b.reload, :approved?

    follow_redirect!
    assert_match "2 listings approved, 1 skipped", flash[:notice]
  end

  test "bulk with no valid ids is reported back" do
    post admin_bulk_moderation_path, params: { decision: "approve", listing_ids: [] }
    assert_response :redirect
    follow_redirect!
    assert_match I18n.t("admin.bulk_moderations.create.none_done"), flash[:alert]
  end

  private

  def duplicate_pending(title)
    listings(:pending).dup.tap do |listing|
      listing.title = title
      listing.slug = title.parameterize
      listing.save!
    end
  end
end
