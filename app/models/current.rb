class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_token, :user

  # Cookie sessions set `session`; API bearer tokens set `user` (and
  # `api_token`) directly. The fallback keeps every existing
  # Current.user call site working for the web.
  def user
    super || session&.user
  end
end
