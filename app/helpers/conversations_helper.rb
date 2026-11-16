module ConversationsHelper
  # Two-letter avatar fallback for inbox rows and thread headers.
  def user_initials(user)
    user.display_name.to_s.split(/[\s\-]+/).filter_map { |part| part[0] }.first(2).join.upcase
  rescue StandardError
    "?"
  end
end
