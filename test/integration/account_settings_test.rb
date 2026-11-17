require "test_helper"

class AccountSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    sign_in_as @user
  end

  test "profile page saves name, phone and language switches the site locale" do
    get account_profile_path
    assert_response :success

    patch account_profile_path, params: {
      user: { first_name: "Ada", last_name: "Lovelace", email_address: "ada@example.com",
              phone: "+34 600 123 456", locale: "de" }
    }
    assert_redirected_to account_profile_path(locale: :de)

    @user.reload
    assert_equal "ada@example.com", @user.email_address
    assert_equal "+34600123456", @user.phone
    assert_equal "de", @user.locale

    get account_profile_path(locale: :de)
    assert_response :success
  end

  test "profile rejects duplicate e-mail addresses" do
    patch account_profile_path, params: { user: { email_address: users(:one).email_address } }
    assert_response :unprocessable_entity
    assert_match "taken", response.body
  end

  test "security requires the current password and changes it" do
    get account_security_path
    assert_response :success

    patch account_security_path, params: {
      user: { current_password: "wrong", password: "brand-new-secret", password_confirmation: "brand-new-secret" }
    }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("password")

    patch account_security_path, params: {
      user: { current_password: "password",
              password: "brand-new-secret", password_confirmation: "brand-new-secret" }
    }
    assert_redirected_to account_security_path
    assert @user.reload.authenticate("brand-new-secret")
  end

  test "notification preferences persist the full matrix" do
    get account_notification_preferences_path
    assert_response :success

    patch account_notification_preferences_path, params: {
      user: { email_new_message: "1", email_price_drop: "1", email_newsletter: "0" }
    }
    assert_redirected_to account_notification_preferences_path

    prefs = @user.reload.notification_preferences
    assert_equal true, prefs["email_new_message"]
    assert_equal false, prefs["email_offers"]
    assert_equal true, prefs["email_price_drop"]
    assert_equal false, prefs["email_newsletter"]
  end

  test "data export request queues the job and redirects to the profile" do
    assert_enqueued_with(job: Users::DataExportJob, args: [ @user ]) do
      post account_data_export_path
    end
    assert_redirected_to account_profile_path
  end

  test "deletion page warns about open orders and blocks the erasure" do
    Order.create!(number: "PCM-TEST-OPEN-2", buyer: @user, seller: users(:one),
                  status: :pending_payment, currency: "EUR",
                  subtotal_cents: 1_000, shipping_cents: 0, total_cents: 1_000)

    get account_deletion_path
    assert_response :success
    assert_select "a[href=?]", orders_path # blocked: points at the open orders

    delete account_deletion_path
    assert_redirected_to account_deletion_path

    @user.reload
    assert_not @user.deleted?
    assert_equal "two@example.com", @user.email_address
  end

  test "deletion anonymizes the account and ends the session" do
    Favorite.create!(user: @user, listing: listings(:featured))

    get account_deletion_path
    assert_response :success

    delete account_deletion_path
    assert_redirected_to root_path

    @user.reload
    assert @user.deleted?
    assert_empty @user.favorites

    get notifications_path
    assert_redirected_to new_session_path
  end
end
