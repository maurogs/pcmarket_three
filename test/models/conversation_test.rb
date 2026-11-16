require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @conversation = Conversation.create!(
      listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
    )
  end

  test "for_user returns only threads where the user is buyer or seller" do
    assert_includes Conversation.for_user(users(:one)), @conversation
    assert_includes Conversation.for_user(users(:two)), @conversation
    assert_not_includes Conversation.for_user(users(:admin)), @conversation
  end

  test "other_party maps each side to the other" do
    assert_equal users(:one), @conversation.other_party(users(:two))
    assert_equal users(:two), @conversation.other_party(users(:one))
  end

  test "unread counts ignore my own messages and read ones" do
    mine = @conversation.messages.create!(sender: users(:two), body: "hi")
    theirs_unread = @conversation.messages.create!(sender: users(:one), body: "hello")
    @conversation.messages.create!(sender: users(:one), body: "old", read_at: Time.current)

    assert_equal 1, @conversation.unread_count_for(users(:two))
    assert_equal 1, @conversation.unread_count_for(users(:one)) # only `mine`
    assert_equal({ @conversation.id => 1 },
                 Conversation.unread_counts_by_conversation_for(users(:two), [ @conversation ]))

    theirs_unread # keep referenced
    mine
  end

  test "mark_messages_read_for only flips the other party's unread messages" do
    @conversation.messages.create!(sender: users(:two), body: "hi")
    theirs = @conversation.messages.create!(sender: users(:one), body: "hello")

    assert_equal 1, @conversation.mark_messages_read_for(users(:two))
    assert theirs.reload.read_at
  end

  test "blocked_by? is true when either direction has a block" do
    Block.create!(blocker: users(:one), blocked: users(:two))
    assert @conversation.blocked_by?(users(:two))
    assert @conversation.blocked_by?(users(:one))
  end

  test "badge count counts threads with unread mail, cached per user" do
    @conversation.messages.create!(sender: users(:one), body: "hello")

    assert_equal 1, Conversation.unread_badge_count_for(users(:two))
    assert_equal 0, Conversation.unread_badge_count_for(users(:one))
  end
end
