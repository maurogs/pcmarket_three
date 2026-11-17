require "test_helper"

class MessagingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @conversation = Conversation.create!(
      listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
    )
  end

  # --- inbox --------------------------------------------------------------

  test "guests are sent to sign in from the inbox" do
    get conversations_path
    assert_redirected_to new_session_path
  end

  test "inbox lists my threads and not other people's" do
    other = Conversation.create!(
      listing: listings(:as_new), buyer: users(:admin), seller: users(:two)
    )

    sign_in_as users(:two)
    get conversations_path
    assert_response :success
    assert_select "a[id=?]", "conversation_#{@conversation.id}", minimum: 1
    assert_select "a[id=?]", "conversation_#{other.id}", minimum: 1

    sign_in_as users(:admin)
    get conversations_path
    assert_select "a[id=?]", "conversation_#{@conversation.id}", count: 0
  end

  test "header badge counts threads with unread mail" do
    @conversation.messages.create!(sender: users(:one), body: "hola")

    sign_in_as users(:two)
    get conversations_path
    assert_select "#unread-conversations-badge span", text: "1"
  end

  # --- starting threads ---------------------------------------------------

  test "message seller creates (or reuses) the thread and redirects into it" do
    sign_in_as users(:two)
    post conversations_path, params: { listing_id: listings(:gigabyte).to_param }
    assert_redirected_to conversation_path(@conversation)

    post conversations_path, params: { listing_id: listings(:gigabyte).to_param }
    assert_redirected_to conversation_path(@conversation)
    assert_equal 1, Conversation.where(listing: listings(:gigabyte), buyer: users(:two)).count
  end

  test "sellers cannot message themselves" do
    sign_in_as users(:one)
    post conversations_path, params: { listing_id: listings(:gigabyte).to_param }

    assert_redirected_to listing_path(listings(:gigabyte))
    assert_equal I18n.t("conversations.create.self"), flash[:alert]
  end

  test "blocked pairs cannot start threads" do
    Block.create!(blocker: users(:one), blocked: users(:two))

    sign_in_as users(:two)
    post conversations_path, params: { listing_id: listings(:gigabyte).to_param }

    assert_redirected_to listing_path(listings(:gigabyte))
    assert_equal I18n.t("conversations.create.blocked"), flash[:alert]
  end

  # --- thread page ---------------------------------------------------------

  test "outsiders 404 on every thread route regardless of id" do
    sign_in_as users(:admin)

    get conversation_path(@conversation)
    assert_response :not_found
    post conversation_messages_path(@conversation), params: { message: { body: "hola" } }
    assert_response :not_found
    post conversation_read_receipt_path(@conversation)
    assert_response :not_found
  end

  test "opening a thread marks the other party's messages read" do
    unread = @conversation.messages.create!(sender: users(:one), body: "hola")

    sign_in_as users(:two)
    get conversation_path(@conversation)
    assert_response :success

    assert unread.reload.read_at
    assert_select "#unread-conversations-badge span", count: 0
  end

  # --- messages ------------------------------------------------------------

  test "participants post messages; turbo replies clear the composer" do
    sign_in_as users(:two)
    post conversation_messages_path(@conversation),
         params: { message: { body: "  ¿sigue disponible?  " } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, %q(turbo-stream action="update" target="message_body")
    assert_equal "¿sigue disponible?", @conversation.messages.sole.body
  end

  test "blank messages come back as 422 turbo errors" do
    sign_in_as users(:two)
    post conversation_messages_path(@conversation),
         params: { message: { body: "   " } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("messages.create.errors.blank")
  end

  test "blocked senders are refused" do
    Block.create!(blocker: users(:one), blocked: users(:two))

    sign_in_as users(:two)
    post conversation_messages_path(@conversation), params: { message: { body: "hola" } }

    assert_response :redirect
    assert_equal I18n.t("messages.create.errors.blocked"), flash[:alert]
  end

  test "a user is capped at 30 messages per minute" do
    sign_in_as users(:two)

    30.times do |i|
      post conversation_messages_path(@conversation), params: { message: { body: "msg #{i}" } }
      assert_response :redirect
    end

    post conversation_messages_path(@conversation), params: { message: { body: "one too many" } }
    assert_response :too_many_requests
  end

  # --- read receipts --------------------------------------------------------

  test "the read receipt endpoint marks the thread read and re-renders the badge" do
    @conversation.messages.create!(sender: users(:one), body: "hola")

    sign_in_as users(:two)
    post conversation_read_receipt_path(@conversation),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    refute @conversation.messages.where(read_at: nil).exists?
    assert_includes response.body, "unread-conversations-badge"
  end

  # --- blocks ----------------------------------------------------------------

  test "blocking stops messaging and unblocking restores it" do
    sign_in_as users(:two)

    post blocks_path, params: { blocked_id: users(:one).id }
    assert_response :redirect
    assert_equal I18n.t("blocks.create.created"), flash[:notice]

    post conversation_messages_path(@conversation), params: { message: { body: "hola" } }
    assert_equal I18n.t("messages.create.errors.blocked"), flash[:alert]

    block = Block.sole
    delete block_path(block)
    assert_equal I18n.t("blocks.destroy.destroyed"), flash[:notice]

    post conversation_messages_path(@conversation), params: { message: { body: "hola" } }
    assert_nil flash[:alert]
  end

  test "you cannot block yourself, and duplicate blocks are refused" do
    sign_in_as users(:two)

    post blocks_path, params: { blocked_id: users(:two).id }
    assert_equal I18n.t("blocks.errors.cannot_block_self"), flash[:alert]

    post blocks_path, params: { blocked_id: users(:one).id }
    assert_equal I18n.t("blocks.create.created"), flash[:notice]
    post blocks_path, params: { blocked_id: users(:one).id }
    assert_equal I18n.t("blocks.errors.taken"), flash[:alert]
  end

  test "blocks are scoped: nobody unblocks on someone else's behalf" do
    block = Block.create!(blocker: users(:one), blocked: users(:two))

    sign_in_as users(:admin)
    delete block_path(block)
    assert_response :not_found
    assert block.reload.persisted?
  end
end
