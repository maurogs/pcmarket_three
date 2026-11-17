require "test_helper"

# Conversations + messages: outsider access must 404 (not 403) and the send
# path stays exclusively inside Messages::Send.
class Api::V1::ConversationsMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @seller = users(:one)
    @buyer = users(:two)
    @outsider = users(:admin)
    @listing = listings(:gigabyte)

    @conversation = Conversation.create!(listing: @listing, buyer: @buyer, seller: @seller)
    @older = Message.create!(conversation: @conversation, sender: @buyer, body: "Hola, sigue disponible?",
                             created_at: 2.days.ago)
    @newer = Message.create!(conversation: @conversation, sender: @seller, body: "Si, aun la tengo",
                             created_at: 1.day.ago)
  end

  test "index shows only my threads with unread counts and paginates" do
    auth_as @seller

    get "/api/v1/conversations", params: { page: 1, per_page: 10 }, headers: json_api_headers
    assert_response :success
    body = json_body
    assert_equal 1, body[:conversations].size

    row = body[:conversations].first
    assert_equal @conversation.id, row[:id]
    assert_equal @listing.slug, row[:listing][:slug]
    assert_equal "Si, aun la tengo", row[:last_message_body]
    # The buyer's bubble is the only unread one for the seller.
    assert_equal 1, row[:unread_for_me]
    assert_equal 1, body[:meta][:pagination][:total]
  end

  test "the other side's unread mail is counted for me" do
    Message.create!(conversation: @conversation, sender: @buyer, body: "Y el envio?")

    auth_as @seller
    get "/api/v1/conversations", headers: json_api_headers

    assert_equal 2, json_body[:conversations].first[:unread_for_me]
  end

  test "show returns the thread and marks the other side's messages read" do
    Message.create!(conversation: @conversation, sender: @buyer, body: "Precio final?")

    auth_as @seller
    get "/api/v1/conversations/#{@conversation.id}", headers: json_api_headers
    assert_response :success
    body = json_body

    assert_equal 3, body[:messages].size
    assert_equal "Hola, sigue disponible?", body[:messages].first[:body]
    buyer_ids = Message.where(sender: @buyer).pluck(:id)
    seller_ids = Message.where(sender: @seller).pluck(:id)
    assert body[:messages].select { |m| buyer_ids.include?(m[:id]) }.all? { |m| m[:read] },
           "the seller opening the thread reads the buyer's bubbles"
    assert body[:messages].select { |m| seller_ids.include?(m[:id]) }.none? { |m| m[:read] },
           "own bubbles are never marked read"
    assert_equal 0, body[:conversation][:unread_for_me]
  end

  test "show 404s for an outsider" do
    auth_as @outsider

    get "/api/v1/conversations/#{@conversation.id}", headers: json_api_headers
    assert_response :not_found
    assert_equal "not_found", json_body[:error][:code]
  end

  test "outsider cannot read or write the messages of a thread" do
    auth_as @outsider

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: json_api_headers
    assert_response :not_found

    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "vendo mi coche" }.to_json,
         headers: json_api_headers
    assert_response :not_found
    assert_equal 2, @conversation.messages.reload.count
  end

  test "messages index paginates backwards with before_id" do
    auth_as @seller

    get "/api/v1/conversations/#{@conversation.id}/messages", params: { limit: 1 }, headers: json_api_headers
    assert_response :success
    body = json_body
    assert_equal 1, body[:messages].size
    assert_equal "Si, aun la tengo", body[:messages].first[:body]
    assert_equal true, body[:meta][:has_more]
    assert_nil body[:meta][:before_id]

    oldest = body[:messages].first[:id]
    get "/api/v1/conversations/#{@conversation.id}/messages",
        params: { limit: 1, before_id: oldest }, headers: json_api_headers
    body = json_body
    assert_equal "Hola, sigue disponible?", body[:messages].first[:body]
    assert_equal false, body[:meta][:has_more]
    assert_equal oldest, body[:meta][:before_id]
  end

  test "creating a message runs through Messages::Send" do
    auth_as @buyer
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post "/api/v1/conversations/#{@conversation.id}/messages",
           params: { body: "La recojo el sabado" }.to_json, headers: json_api_headers
    end
    assert_response :created

    message = json_body[:message]
    assert_equal "La recojo el sabado", message[:body]
    assert_equal "text", message[:kind]
    assert_equal @buyer.id, message[:sender_id]
    assert_equal 3, @conversation.messages.reload.count
    assert_operator @conversation.reload.last_message_at, :>=, @newer.created_at
  end

  test "sending to a blocked counterpart is rejected" do
    Block.create!(blocker: @seller, blocked: @buyer)

    auth_as @buyer
    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "hola" }.to_json, headers: json_api_headers

    assert_response :unprocessable_entity
    assert_equal "blocked", json_body[:error][:code]
    assert_equal 2, @conversation.messages.reload.count
  end

  test "a blank or over-long body is a validation error with field details" do
    auth_as @buyer

    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "   " }.to_json, headers: json_api_headers
    assert_response :unprocessable_entity
    body = json_body
    assert_equal "invalid_request", body[:error][:code]
    assert body[:error][:details][:body].present?

    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "x" * (Message::MAX_BODY_LENGTH + 1) }.to_json, headers: json_api_headers
    assert_response :unprocessable_entity
    assert json_body[:error][:details][:body].present?
    assert_equal 2, @conversation.messages.reload.count
  end
end
