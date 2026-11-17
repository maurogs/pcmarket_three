require "test_helper"

# Native apps have no session cookie, so the same ApiToken rows the JSON
# API uses authenticate the WebSocket: ?token= or an Authorization header.
# Anonymous sockets and dead tokens are rejected outright.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with a bearer token in the params" do
    user = users(:one)
    connect "/cable", params: { token: ApiToken.issue_for(user) }

    assert_equal user.id, connection.current_user.id
  end

  test "connects with an Authorization header" do
    user = users(:two)
    connect "/cable", headers: { "Authorization" => "Bearer #{ApiToken.issue_for(user)}" }

    assert_equal user.id, connection.current_user.id
  end

  test "rejects an anonymous socket" do
    assert_reject_connection { connect "/cable" }
  end

  test "rejects a token that is not an active api token" do
    assert_reject_connection { connect "/cable?token=not-a-real-token" }
  end
end
