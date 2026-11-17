require "test_helper"

# Contact form submissions (Phase 7b): stored, mailed to support, and
# throttled to a handful per half hour per client.
class ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  def payload(overrides = {})
    { contact_message: { name: "Ana López", email: "ana@example.com",
                         subject: "A question about an order",
                         body: "My parcel has not moved in four days, what can I do?" }.merge(overrides) }
  end

  test "a valid submission stores the message and queues the support e-mail" do
    assert_difference "ContactMessage.count" do
      assert_enqueued_emails 1 do
        post contact_messages_path, params: payload
      end
    end

    assert_redirected_to page_path("contact")
    assert_equal I18n.t("contact_messages.create.created"), flash[:notice]

    message = ContactMessage.last
    assert_equal "en", message.locale
    assert_equal "Ana López", message.name
    assert_equal "A question about an order", message.subject
  end

  test "the stored locale follows the request locale" do
    post contact_messages_path(locale: :fr), params: payload
    assert_equal "fr", ContactMessage.last.locale
  end

  test "an invalid submission bounces back without storing anything" do
    assert_no_difference "ContactMessage.count" do
      post contact_messages_path, params: payload(body: "short")
    end

    assert_redirected_to page_path("contact")
    assert_not flash[:alert].blank?
  end

  test "the rate limit cuts the sixth message within half an hour" do
    5.times do
      post contact_messages_path, params: payload
      assert_redirected_to page_path("contact")
    end
    assert_equal 5, ContactMessage.count

    post contact_messages_path, params: payload
    assert_redirected_to page_path("contact")
    assert_equal I18n.t("contact_messages.create.rate_limited"), flash[:alert]
    assert_equal 5, ContactMessage.count
  end

  test "with no support address configured the row is kept but nothing is delivered" do
    Setting.set("support_email", "")

    assert_enqueued_emails 1 do
      post contact_messages_path, params: payload
    end
    assert_equal 1, ContactMessage.count

    perform_enqueued_jobs
    assert_empty ActionMailer::Base.deliveries
  end
end
