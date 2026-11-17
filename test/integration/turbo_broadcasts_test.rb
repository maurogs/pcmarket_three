require "test_helper"

# Real-time contract of the thread: every message appends a bubble to the
# thread stream (every open conversation page) and replaces the inbox row on
# each participant's personal [user, :inbox] stream, so inboxes reorder with
# an unread badge without a page refresh.
class TurboBroadcastsTest < ActionDispatch::IntegrationTest
  setup do
    @conversation = Conversation.create!(
      listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
    )
  end

  test "a sent message appends to the thread stream and refreshes both inboxes" do
    thread_broadcasts = nil

    buyer_inbox = capture_turbo_stream_broadcasts([ users(:two), :inbox ]) do
      seller_inbox = capture_turbo_stream_broadcasts([ users(:one), :inbox ]) do
        thread_broadcasts = capture_turbo_stream_broadcasts(@conversation) do
          Messages::Send.call(conversation: @conversation, sender: users(:two), body: "¿sigue disponible?")
        end
      end
      assert_equal 1, seller_inbox.size
      assert_equal "conversation_#{@conversation.id}", seller_inbox.first["target"]
      assert_includes seller_inbox.first.to_html, %(id="conversation_#{@conversation.id}")
      assert_includes seller_inbox.first.to_html, users(:two).display_name
    end

    assert_equal 1, thread_broadcasts.size
    bubble = thread_broadcasts.first
    assert_equal "append", bubble["action"]
    assert_equal "messages", bubble["target"]
    assert_includes bubble.to_html, "¿sigue disponible?"

    assert_equal 1, buyer_inbox.size
    assert_equal "conversation_#{@conversation.id}", buyer_inbox.first["target"]
  end

  test "the thread and inbox pages carry their stream subscriptions" do
    sign_in_as users(:two)

    get conversation_path(@conversation)
    assert_response :success
    assert_select "turbo-cable-stream-source[channel=?]", "Turbo::StreamsChannel", count: 3 # thread + inbox rail + notification bell

    get conversations_path
    assert_select "turbo-cable-stream-source[channel=?]", "Turbo::StreamsChannel", minimum: 1
  end
end
