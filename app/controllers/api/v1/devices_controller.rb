module Api
  module V1
    # Push-token registry for native apps (nothing sends yet — Device is
    # the storage Phase 8 planned ahead). Creation is idempotent on
    # (user, push_token): re-registering an existing token just refreshes
    # its platform, so app reinstalls and token rotations never 409.
    # Tokens come back truncated — never echo the full push token.
    class DevicesController < BaseController
      before_action :verify_user!

      def index
        @devices = current_user.devices.order(created_at: :desc)
      end

      def create
        device = current_user.devices.find_or_initialize_by(
          push_token: params.require(:push_token).to_s
        )
        device.platform = params[:platform]
        device.save!
        @device = device
        render :create, status: :created
      end

      def destroy
        current_user.devices.find(params[:id]).destroy!
        render json: { message: t("api.devices.destroyed") }
      end
    end
  end
end
