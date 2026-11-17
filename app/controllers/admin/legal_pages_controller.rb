module Admin
  # Legal pages CRUD (country × locale × slug). Bodies are Markdown edited
  # in a plain textarea and rendered through a safe pipeline
  # (CommonMarker + sanitize — see LegalPagesHelper#legal_markdown), with a
  # live preview on show and "copy from another locale" prefills on new/edit.
  class LegalPagesController < BaseController
    include Auditable

    before_action :set_legal_page, only: %i[show edit update destroy]

    def index
      scope = LegalPage.order(:country_code, :locale, :slug)
      scope = scope.where(country_code: params[:country]) if params[:country].present?
      scope = scope.where(locale: params[:locale]) if params[:locale].presence_in(I18n.available_locales.map(&:to_s))
      @pagy, @legal_pages = pagy(scope, limit: 30)
    end

    def show; end

    def new
      source = copy_source(params[:country_code], params[:locale], params[:slug])
      @legal_page = LegalPage.new(
        country_code: params[:country_code].presence_in(Country.pluck(:code)) || Country.enabled.first&.code,
        locale: normalize_locale_param(params[:locale]),
        slug: params[:slug].presence_in(LegalPage::SLUGS),
        title: source&.title,
        body: source&.body
      )
    end

    def create
      @legal_page = LegalPage.new(legal_page_params)

      if @legal_page.save
        audit!("legal_page_create", @legal_page,
               country_code: @legal_page.country_code, locale: @legal_page.locale, slug: @legal_page.slug)
        redirect_to admin_legal_pages_path, notice: t(".created", slug: @legal_page.slug)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @copy_source = copy_source(@legal_page.country_code, params[:copy_from], @legal_page.slug)
    end

    def update
      @legal_page.assign_attributes(legal_page_params)

      if @legal_page.save
        audit!("legal_page_update", @legal_page,
               slug: @legal_page.slug, locale: @legal_page.locale, published: @legal_page.published)
        redirect_to admin_legal_pages_path, notice: t(".updated", slug: @legal_page.slug)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @legal_page.destroy!
      audit!("legal_page_destroy", @legal_page,
             slug: @legal_page.slug, locale: @legal_page.locale, country_code: @legal_page.country_code)
      redirect_to admin_legal_pages_path, notice: t(".destroyed", slug: @legal_page.slug)
    end

    private

    def set_legal_page
      @legal_page = LegalPage.find(params[:id])
    end

    def legal_page_params
      params.require(:legal_page).permit(:country_code, :locale, :slug, :title, :body, :published)
    end

    def copy_source(country_code, locale, slug)
      locale = normalize_locale_param(locale)
      slug = slug.presence_in(LegalPage::SLUGS)
      return nil if locale.nil? || slug.nil?

      LegalPage.find_by(country_code: country_code.presence || "ES", locale: locale, slug: slug)
    end

    def normalize_locale_param(locale)
      locale.presence_in(I18n.available_locales.map(&:to_s))
    end
  end
end
