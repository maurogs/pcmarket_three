module Account
  # GDPR data export: queues the JSON build; the signed link arrives by
  # email (7 days).
  class DataExportsController < BaseController
    def create
      Users::DataExportJob.perform_later(current_user)
      redirect_to account_profile_path, notice: t(".queued")
    end
  end
end
