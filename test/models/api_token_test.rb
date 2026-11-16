require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "issue_for returns the clear token once and stores only its sha256 digest" do
    raw = ApiToken.issue_for(users(:one))
    token = ApiToken.sole
    assert_equal raw.length, ApiToken::TOKEN_LENGTH
    assert_equal ApiToken.digest_for(raw), token.token_digest
    refute_equal raw, token.token_digest
  end

  test "authenticate finds the token and stamps last_used_at" do
    raw = ApiToken.issue_for(users(:one))
    token = ApiToken.authenticate(raw)
    assert_equal users(:one), token.user
    assert_not_nil token.last_used_at
  end

  test "authenticate returns nil for an unknown token" do
    assert_nil ApiToken.authenticate("nope")
  end

  test "authenticate returns nil for an expired token" do
    raw = ApiToken.issue_for(users(:one), expires_at: 1.day.ago)
    assert_nil ApiToken.authenticate(raw)
  end
end
