require "test_helper"

module Messages
  class SendTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

    setup do
      @conversation = Conversation.create!(
        listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
      )
    end

    test "participants can write; the body is stripped" do
      result = Messages::Send.call(conversation: @conversation, sender: users(:two), body: "  hola  ")

      assert_nil result.error
      assert_equal "hola", result.message.body
      assert_equal "text", result.message.kind
    end

    test "outsiders cannot post into a thread" do
      result = Messages::Send.call(conversation: @conversation, sender: users(:admin), body: "hola")

      assert_equal :not_participant, result.error
      assert_empty @conversation.messages
    end

    test "a block in either direction stops messages" do
      Block.create!(blocker: users(:one), blocked: users(:two))
      assert_equal :blocked, Messages::Send.call(conversation: @conversation, sender: users(:two), body: "hola").error

      Block.delete_all
      Block.create!(blocker: users(:two), blocked: users(:one))
      assert_equal :blocked, Messages::Send.call(conversation: @conversation, sender: users(:two), body: "hola").error
    end

    test "blank and over-long bodies are rejected" do
      assert_equal :blank, Messages::Send.call(conversation: @conversation, sender: users(:two), body: "   ").error
      assert_equal :too_long,
                   Messages::Send.call(conversation: @conversation, sender: users(:two), body: "a" * 2001).error
    end

    test "the recipient gets an unread notification and one e-mail" do
      Messages::Send.call(conversation: @conversation, sender: users(:two), body: "hola")

      notification = Notification.find_by!(user: users(:one), kind: "new_message")
      assert_nil notification.read_at
      assert_equal @conversation.id, notification.payload["conversation_id"]
      assert_enqueued_emails 1
    end

    test "e-mail is suppressed while the recipient has unread new_message mail for this thread" do
      Messages::Send.call(conversation: @conversation, sender: users(:two), body: "primera")
      assert_equal 1, Notification.where(user: users(:one), kind: "new_message").count

      Messages::Send.call(conversation: @conversation, sender: users(:two), body: "segunda")
      assert_equal 2, Notification.where(user: users(:one), kind: "new_message").count

      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
    end

    test "old unread notifications do not suppress a fresh e-mail" do
      Notification.create!(
        user: users(:one), kind: "new_message",
        payload: { "conversation_id" => @conversation.id }, created_at: 3.hours.ago
      )

      Messages::Send.call(conversation: @conversation, sender: users(:two), body: "hola")
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
    end
  end
end
