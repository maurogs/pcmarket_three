module Api
  module V1
    # GET /api/v1/countries — enabled countries for address forms.
    class CountriesController < BaseController
      skip_before_action :authenticate_token!

      def index
        countries = Country.enabled.order(:code)
        render json: {
          countries: countries.map { |country| { code: country.code, name: t(country.name_key) } }
        }
      end
    end
  end
end
