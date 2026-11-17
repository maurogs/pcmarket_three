module Api
  module V1
    # Address book for checkout. Address owns the validation rules (postal
    # code per country, known region) and the single-default invariant —
    # RecordInvalid turns bad payloads into the standard 422 envelope.
    class AddressesController < BaseController
      before_action :verify_user!
      before_action :set_address, only: %i[update destroy]

      def index
        @addresses = current_user.addresses.order(Arel.sql('"addresses"."default" DESC, "addresses"."id"'))
      end

      def create
        @address = current_user.addresses.new(address_params)
        @address.save!
        render :create, status: :created
      end

      def update
        @address.update!(address_params)
        render :update
      end

      def destroy
        @address.destroy!
        head :no_content
      end

      private

        def set_address
          @address = current_user.addresses.find(params[:id])
        end

        def address_params
          params.permit(:full_name, :line1, :line2, :city, :region,
                        :postal_code, :country_code, :phone, :default)
        end
    end
  end
end
