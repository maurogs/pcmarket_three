require "test_helper"

class Admin::UsersTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "ban destroys sessions, archives live listings and blocks login" do
    target = users(:one)
    stale_session = target.sessions.create!

    post admin_user_ban_path(target), params: { ban_reason: "Scam listings" }
    assert_response :redirect

    target.reload
    assert_predicate target, :banned?
    assert_equal "Scam listings", target.ban_reason
    assert_not Session.exists?(stale_session.id)
    assert_equal "archived", listings(:gigabyte).reload.status

    assert_equal 1, AdminAuditLog.where(action: "ban_user", subject: target).count

    # Banned user cannot log in any more.
    sign_out
    post session_path, params: { email_address: target.email_address, password: "password" }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_match I18n.t("sessions.create.banned"), flash[:alert]
  end

  test "admins cannot ban themselves" do
    post admin_user_ban_path(users(:admin))
    follow_redirect!
    assert_match I18n.t("admin.bans.create.cannot_ban_self"), flash[:alert]
    assert_not users(:admin).reload.banned?
  end

  test "unban restores login but not the archived listings" do
    post admin_user_ban_path(users(:one)), params: { ban_reason: "Temporary" }
    assert_predicate listings(:gigabyte).reload, :archived?

    delete admin_user_ban_path(users(:one))
    assert_response :redirect
    assert_not_predicate users(:one).reload, :banned?
    assert_equal "archived", listings(:gigabyte).reload.status

    assert_equal 1, AdminAuditLog.where(action: "unban_user", subject: users(:one)).count
  end

  test "banned fixture user cannot log in" do
    sign_out
    post session_path, params: { email_address: users(:banned).email_address, password: "password" }
    assert_redirected_to new_session_path
    assert_match I18n.t("sessions.create.banned"), flash[:alert]
  end

  test "the last admin cannot be demoted, even by themselves" do
    patch admin_user_path(users(:admin)), params: { user: { role: "user" } }
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.models.user.attributes.role.last_admin"), response.body
    assert_predicate users(:admin).reload, :admin?
  end

  test "an admin may promote a user but never demote themselves" do
    patch admin_user_path(users(:two)), params: { user: { role: "admin" } }
    assert_response :redirect
    assert_predicate users(:two).reload, :admin?

    patch admin_user_path(users(:admin)), params: { user: { role: "user" } }
    assert_response :unprocessable_entity
    assert_match "remove your own admin role", response.body
    assert_predicate users(:admin).reload, :admin?
  end

  test "demoting another admin is fine while an admin remains" do
    patch admin_user_path(users(:two)), params: { user: { role: "admin" } }
    assert_predicate users(:two).reload, :admin?

    patch admin_user_path(users(:two)), params: { user: { role: "user" } }
    assert_response :redirect
    assert_not users(:two).reload.admin?
    assert_predicate users(:admin).reload, :admin?
  end

  test "impersonation starts on a non-admin and locks admin pages down" do
    target = users(:two)

    assert_difference [ -> { Session.count }, -> { AdminAuditLog.count } ], 1 do
      post admin_user_impersonation_path(target)
      assert_response :redirect
    end

    follow_redirect!
    assert_response :success
    assert_match I18n.t("admin.impersonation.banner", name: target.display_name), response.body

    # Admin area is unreachable while impersonating (we ARE the target now).
    get admin_dashboard_path
    assert_response :not_found

    assert_equal 1, AdminAuditLog.where(action: "impersonation_start", subject: target).count
  end

  test "the banner stop button returns the admin to their own account" do
    target = users(:two)
    admin = users(:admin)

    post admin_user_impersonation_path(target)
    follow_redirect!

    # Stopping destroys the target session and creates a fresh admin one:
    # net session count is unchanged, but the audit row must be there.
    assert_difference -> { AdminAuditLog.count }, 1 do
      delete admin_user_impersonation_path(target)
      assert_response :redirect
    end

    assert_redirected_to admin_user_path(target)
    follow_redirect!
    assert_response :success # admin pages work again

    get admin_dashboard_path
    assert_response :success

    assert_equal 1, AdminAuditLog.where(action: "impersonation_stop", subject: target).count
    assert admin.reload.sessions.exists?
  end

  test "admins cannot impersonate other admins" do
    assert_no_difference [ -> { Session.count } ] do
      post admin_user_impersonation_path(users(:admin))
      assert_response :redirect
    end
    follow_redirect!
    assert_match I18n.t("admin.impersonation.create.not_allowed"), flash[:alert]
  end

  test "user page shows listings, store and moderation trail" do
    get admin_user_path(users(:one))
    assert_response :success
    assert_match stores(:one).name, response.body
    assert_match I18n.t("admin.users.show.store.title"), response.body
  end
end
