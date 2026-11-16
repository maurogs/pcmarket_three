require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid user" do
    user = User.new(
      email_address: "valid@example.com",
      username: "valid_user-01",
      password: "correct horse battery staple",
      password_confirmation: "correct horse battery staple",
      first_name: "Ada",
      last_name: "Lovelace",
      phone: "+34 600 123 456"
    )

    assert user.valid?, user.errors.full_messages.to_sentence
    assert user.user?, "default role should be :user"
  end

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "normalized email_address is persisted" do
    user = users(:one)
    user.update!(email_address: "  Renamed@Example.COM ")
    assert_equal("renamed@example.com", user.reload.email_address)
  end

  test "email_address must be a valid address and unique" do
    user = User.new(email_address: "not-an-email", username: "format_check", password: "secret123")
    assert_not user.valid?
    assert_includes(error_types(user, :email_address), :invalid)

    duplicate = User.new(email_address: users(:two).email_address, username: "duplicate_email", password: "secret123")
    assert_not duplicate.valid?
    assert_includes(error_types(duplicate, :email_address), :taken)
  end

  test "invalid usernames are rejected" do
    [ "ab", "a b", "no.dots", "dollar$symbol", "way_too_long_username_over_thirty_characters_long", "" ].each do |username|
      user = User.new(email_address: "unique-#{SecureRandom.hex(4)}@example.com", username: username, password: "secret123")
      assert_not user.valid?, "expected #{username.inspect} to be invalid"
      assert_includes(error_types(user, :username), :invalid)
    end
  end

  test "valid usernames are accepted" do
    [ "abc", "a-b_C", "3xtra", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5" ].each do |username|
      user = User.new(email_address: "unique-#{SecureRandom.hex(4)}@example.com", username: username, password: "secret123")
      assert user.valid?, "expected #{username.inspect} to be valid: #{user.errors.full_messages.to_sentence}"
    end
  end

  test "username must be unique" do
    user = User.new(email_address: "another@example.com", username: users(:one).username, password: "secret123")
    assert_not user.valid?
    assert_includes(error_types(user, :username), :taken)
  end

  private
    # Locale-independent error keys (e.g. :invalid, :taken) so assertions hold
    # no matter which locale the model runs under.
    def error_types(record, attribute)
      record.errors.details.fetch(attribute, []).map { |detail| detail[:error] }
    end
end
