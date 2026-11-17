module Api
  module V1
    # Active Storage direct uploads over bearer auth. ActiveStorage's own
    # DirectUploadsController is cookie + CSRF protected (unusable from a
    # native app), so this mirrors its exact request/response shape on top
    # of the API auth; the returned signed_id goes into listing create/
    # update `photos` arrays.
    class DirectUploadsController < BaseController
      # Rails' own direct-upload controller sets this; without it the disk
      # service cannot build the signed PUT URL (Missing host).
      include ActiveStorage::SetCurrent

      before_action :verify_user!

      def create
        blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)

        render json: blob.as_json(root: false, methods: :signed_id).merge(
          direct_upload: {
            url: blob.service_url_for_direct_upload,
            headers: blob.service_headers_for_direct_upload.as_json
          }
        ), status: :created
      end

      private

        def blob_args
          params.expect(blob: [ :filename, :byte_size, :checksum, :content_type, metadata: {} ]).to_h.symbolize_keys
        end
    end
  end
end
