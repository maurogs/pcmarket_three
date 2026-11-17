module Users
  # Profile/role edits performed by an admin from the users screen. The two
  # role guards live here (not in model validations, which would also hit
  # the user's own profile form): an admin may never demote themselves, and
  # the platform may never run out of admins.
  class AdminUpdate
    Result = Struct.new(:user, :saved?, keyword_init: true)

    def self.call(user, raw, acting_admin:)
      new(user, raw, acting_admin).call
    end

    def initialize(user, raw, acting_admin)
      @user = user
      @raw = raw.to_h.symbolize_keys
      @acting_admin = acting_admin
    end

    def call
      user.assign_attributes(profile_attrs)
      role_error = user.invalid? ? nil : apply_role
      if role_error
        # Errors added here would be cleared by save's validation run, and
        # the role was deliberately not assigned — skip the save entirely.
        user.errors.add(:role, role_error)
        saved = false
      else
        saved = user.save
      end
      Result.new(user: user, saved?: saved)
    end

    private

    attr_reader :user, :raw, :acting_admin

    def profile_attrs
      raw.slice(:first_name, :last_name, :email_address, :username,
                :country_code, :locale)
    end

    # Returns an error-key symbol when the role change is blocked, nil when
    # applied. Guard order matters: demoting the last admin is what stays
    # broken for everyone, so it wins over the self-demotion message.
    def apply_role
      return nil unless raw.key?(:role) && raw[:role].present?

      target = raw[:role].to_s
      return nil unless User.roles.key?(target)
      return nil if user.role == target

      if user.admin? && target != "admin"
        return :last_admin if User.admin.where.not(id: user.id).none?
        return :cannot_demote_self if user.id == acting_admin.id
      end

      user.role = target
      nil
    end
  end
end
