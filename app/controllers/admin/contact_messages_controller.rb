module Admin
  # Contact-form inbox (Phase 7b): read-only list + detail. Submissions
  # arrive from the public contact form; support answers out-of-band (the
  # e-mail copy already went to the support address).
  class ContactMessagesController < BaseController
    def index
      scope = ContactMessage.recent
      # `locale` is the public-site routing segment, so the inbox filter uses
      # its own param name; unknown values are simply ignored.
      scope = scope.where(locale: params[:lang]) if params[:lang].presence_in(I18n.available_locales.map(&:to_s))
      @pagy, @messages = pagy(scope, limit: 25)
    end

    def show
      @message = ContactMessage.find(params[:id])
    end
  end
end
