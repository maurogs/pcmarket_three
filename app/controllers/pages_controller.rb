class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[home show]

  # Static content pages (Phase 7b). Anything outside this whitelist is a
  # 404 — no Page model, no admin editing surface: the copy lives in the
  # templates and comes from I18n.
  PAGE_SLUGS = %w[about how-it-works selling help contact seller-guides].freeze

  def home
  end

  def show
    @slug = params[:slug].to_s
    return head :not_found unless PAGE_SLUGS.include?(@slug)

    @contact_message = ContactMessage.new if @slug == "contact"
    # about → pages/about, how-it-works → pages/how_it_works, …
    render "pages/#{@slug.tr("-", "_")}"
  end
end
