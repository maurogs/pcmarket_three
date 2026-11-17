module Api
  module V1
    # Serves the Redoc documentation page (show) and the hand-written OpenAPI
    # 3.1 spec (openapi) from public/api/v1/openapi.yaml. Both are public.
    class DocsController < BaseController
      skip_before_action :authenticate_token!

      def show
        render layout: false
      end

      def openapi
        send_file Rails.root.join("public/api/v1/openapi.yaml"),
                  type: "application/yaml", disposition: "inline"
      end
    end
  end
end
