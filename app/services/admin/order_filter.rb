module Admin
  # Builds the filtered Order relation for the admin orders/disputes
  # indexes. Whitelisted params only; unparseable dates are ignored.
  class OrderFilter
    PROVIDERS = %w[stripe direct].freeze

    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params
    end

    def call
      scope = Order.all
      scope = scope.where(status: params[:status]) if params[:status].presence_in(Order.statuses.keys)
      scope = apply_people(scope, :seller, params[:seller])
      scope = apply_people(scope, :buyer, params[:buyer])
      scope = apply_provider(scope)
      scope = apply_created_range(scope)
      scope = scope.where("number ILIKE ?", "%#{Order.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present?
      scope.recent
    end

    private

    attr_reader :params

    def apply_people(scope, role, term)
      return scope if term.blank?

      like = "%#{Order.sanitize_sql_like(term.strip)}%"
      users = User.where("username ILIKE :like OR email_address ILIKE :like", like: like).select(:id)
      scope.where(role => users)
    end

    def apply_provider(scope)
      case params[:provider]
      when "stripe" then scope.where(payment_provider: "stripe")
      when "direct" then scope.where(payment_provider: nil)
      else scope
      end
    end

    def apply_created_range(scope)
      from = parse_date(params[:from])
      to = parse_date(params[:to])
      scope = scope.where(created_at: from.beginning_of_day..) if from
      scope = scope.where(created_at: ..to.end_of_day) if to
      scope
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
