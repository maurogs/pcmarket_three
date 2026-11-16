require "test_helper"

module Conversations
  class StartTest < ActiveSupport::TestCase
    test "creates the thread between buyer and seller" do
      result = Conversations::Start.call(user: users(:two), listing: listings(:gigabyte))

      assert_nil result.error
      conversation = result.conversation
      assert_equal users(:two), conversation.buyer
      assert_equal users(:one), conversation.seller
      assert_equal listings(:gigabyte), conversation.listing
    end

    test "is idempotent for the same buyer and listing" do
      first = Conversations::Start.call(user: users(:two), listing: listings(:gigabyte)).conversation
      second = Conversations::Start.call(user: users(:two), listing: listings(:gigabyte)).conversation

      assert_equal first, second
      assert_equal 1, Conversation.where(listing: listings(:gigabyte), buyer: users(:two)).count
    end

    test "sellers cannot start a thread on their own listing" do
      result = Conversations::Start.call(user: users(:one), listing: listings(:gigabyte))

      assert_equal :self, result.error
      assert_nil result.conversation
    end

    test "a block in either direction stops new threads" do
      Block.create!(blocker: users(:one), blocked: users(:two))
      assert_equal :blocked, Conversations::Start.call(user: users(:two), listing: listings(:gigabyte)).error

      Block.delete_all
      Block.create!(blocker: users(:two), blocked: users(:one))
      assert_equal :blocked, Conversations::Start.call(user: users(:two), listing: listings(:gigabyte)).error
    end

    test "vacation-mode sellers can still be contacted" do
      listings(:gigabyte).store.enable_vacation!

      result = Conversations::Start.call(user: users(:two), listing: listings(:gigabyte))
      assert_nil result.error
      assert_not_nil result.conversation
    end
  end
end
