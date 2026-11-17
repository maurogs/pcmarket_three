# GET /legal/:slug — public legal-page delivery (Phase 7b). Resolution
# chain: (current country, current locale) → English → the country's
# default locale; 404 when nothing published exists. Readers served a
# fallback language get a notice with a link to that locale.
class LegalPagesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    slug = params[:slug].to_s
    return head :not_found unless LegalPage::SLUGS.include?(slug)

    @page = LegalPage.find_public(country_code: current_country_code,
                                  locale: I18n.locale.to_s, slug: slug)
    return head :not_found if @page.nil?

    @fallback_locale = @page.locale unless @page.locale == I18n.locale.to_s
    @rendered = LegalPages::Render.call(@page)
    @identity = Setting.legal_identity
  end
end
