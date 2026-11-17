module Account
  # GDPR erasure: the danger zone. The confirmation page explains that
  # open orders block deletion; on success the session is destroyed.
  class DeletionsController < BaseController
    def show
      @open_orders_count = Users::Anonymize.open_orders_count(current_user)
    end

    def destroy
      Users::Anonymize.call(current_user)
      session.destroy
      redirect_to root_path, notice: t(".done")
    rescue Users::Anonymize::OpenOrderError
      redirect_to account_deletion_path, alert: t(".blocked")
    end
  end
end
