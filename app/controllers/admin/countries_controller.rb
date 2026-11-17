module Admin
  # Country launch toggles (Phase 6b): edit currency/locale/VAT and flip
  # `enabled` — the Country model blocks enabling until every legal page is
  # published in the country's default locale (the checklist below shows
  # what is missing).
  class CountriesController < BaseController
    include Auditable

    before_action :set_country, only: %i[edit update]

    def index
      @countries = Country.order(enabled: :desc, code: :asc)
    end

    def edit; end

    def update
      @country.assign_attributes(country_params)

      if @country.save
        audit!("country_update", @country,
               code: @country.code, enabled: @country.enabled,
               currency: @country.currency, default_locale: @country.default_locale)
        redirect_to admin_countries_path, notice: t(".updated", code: @country.code)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_country
      @country = Country.find(params[:id])
    end

    def country_params
      params.require(:country).permit(:currency, :default_locale, :vat_rate, :enabled)
    end
  end
end
