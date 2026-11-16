require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @conversation = Conversation.create!(
      listing: listings(:gigabyte), buyer: users(:two), seller: users(:one)
    )
  end

  test "body is required and capped at 2000 characters" do
    assert_not @conversation.messages.create(sender: users(:two), body: " ").valid?
    assert_not @conversation.messages.create(sender: users(:two), body: "a" * 2001).valid?
    assert @conversation.messages.create(sender: users(:two), body: "a" * 2000)
  end

  test "creating a message touches the conversation's last_message_at" do
    message = @conversation.messages.create!(sender: users(:two), body: "hi")
    assert_equal message.created_at.to_i, @conversation.reload.last_message_at.to_i
  end

  test "safety_flagged? detects phones, e-mails and off-platform payment words" do
    [ "llámame al 612 345 678",
      "+34 612345678",
      "mi correo es vendedor@ejemplo.com",
      "te paso mi bizum",
      "págame por paypal",
      "hacemos una transferencia" ].each do |body|
      message = @conversation.messages.new(sender: users(:two), body: body)
      assert message.safety_flagged?, "expected flag: #{body}"
    end
  end

  test "safety_flagged? leaves normal negotiation alone" do
    [ "¿sigue disponible?", "te la dejo a 550 €", "envío a Barcelona incluido" ].each do |body|
      message = @conversation.messages.new(sender: users(:two), body: body)
      assert_not message.safety_flagged?, "unexpected flag: #{body}"
    end
  end
end
