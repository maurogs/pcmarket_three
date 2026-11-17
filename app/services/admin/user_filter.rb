module Admin
  # Filter/sort builder for the users index (role, ban state, country,
  # signup window, has-store, e-mail/username search).
  class UserFilter
    def self.call(params)
      scope = User.all

      scope = scope.where(role: params[:role]) if params[:role].presence_in(User.roles.keys)
      case params[:banned]
      when "yes" then scope = scope.where.not(banned_at: nil)
      when "no" then scope = scope.where(banned_at: nil)
      end
      scope = scope.where(country_code: params[:country]) if params[:country].present?
      scope = scope.where(created_at: Date.parse(params[:signup_from]).beginning_of_day..) if valid_date?(params[:signup_from])
      scope = scope.where(created_at: ..Date.parse(params[:signup_to]).end_of_day) if valid_date?(params[:signup_to])
      case params[:has_store]
      when "yes" then scope = scope.where(id: Store.select(:user_id))
      when "no" then scope = scope.where.not(id: Store.select(:user_id))
      end
      if params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("email_address ILIKE :q OR username ILIKE :q", q: like)
      end

      scope.order(created_at: :desc, id: :desc)
    end

    def self.valid_date?(value)
      return false if value.blank?

      Date.parse(value.to_s)
      true
    rescue ArgumentError
      false
    end
  end
end
