module Admin
  # Newsletter subscriber list: search + locale filter, CSV export
  # (formula-safe) and unsubscribe/destroy.
  class NewsletterSubscriptionsController < BaseController
    include Auditable

    def index
      scope = NewsletterSubscription.order(created_at: :desc, id: :desc)
      if params[:q].present?
        scope = scope.where("email ILIKE ?", "%#{NewsletterSubscription.sanitize_sql_like(params[:q].strip)}%")
      end
      scope = scope.where(locale: params[:locale]) if params[:locale].presence_in(I18n.available_locales.map(&:to_s))

      if request.format.csv?
        send_data NewsletterSubscriptions::CsvExport.build(scope),
                  filename: "pcmarket-newsletter-#{Date.current}.csv", type: "text/csv"
        return
      end

      @pagy, @subscriptions = pagy(scope, limit: 25)
    end

    def destroy
      subscription = NewsletterSubscription.find(params[:id])
      subscription.destroy!
      audit!("newsletter_subscription_destroy", subscription, email: subscription.email)
      redirect_to admin_newsletter_subscriptions_path, notice: t(".destroyed", email: subscription.email)
    end
  end
end
