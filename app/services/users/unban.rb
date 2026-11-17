module Users
  # Counterpart of Users::Ban: clears banned_at/ban_reason. Archived
  # listings are deliberately NOT restored (an admin re-approves them).
  class Unban
    def self.call(user)
      user.unban!
      user
    end
  end
end
