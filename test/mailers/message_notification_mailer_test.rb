require "test_helper"

class MessageNotificationMailerTest < ActionMailer::TestCase
  setup do
    @conversation = Conversation.create!(
      listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
    )
    @message = @conversation.messages.create!(sender: users(:two), body: "hola, sigue disponible?")
  end

  test "new_message points the recipient back into the thread" do
    email = MessageNotificationMailer.with(recipient: users(:one), message: @message).new_message

    assert_equal [ users(:one).email_address ], email.to
    assert_match I18n.t("message_notification_mailer.new_message.subject",
                        sender: users(:two).display_name,
                        locale: users(:one).locale), email.subject
    assert_match @message.body, email.body.encoded
    assert_match "/conversations/#{@conversation.id}", email.body.encoded
  end
end
