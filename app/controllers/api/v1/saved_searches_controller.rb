module Api
  module V1
    # Saved searches. A saved search stores exactly the browse filter
    # params (SavedSearch.new_from_search — the 25-per-user cap is a model
    # validation), so clients can re-run it via GET /v1/listings and the
    # response carries the ready-made web results URL.
    class SavedSearchesController < BaseController
      def index
        @saved_searches = Current.user.saved_searches.includes(:category)
                                 .order(created_at: :desc)
      end

      def create
        @saved_search = SavedSearch.new_from_search(
          user: Current.user, name: params[:name],
          search_filters: (params[:query] || params[:filters] || {})
        )

        unless @saved_search.save
          render_error(:unprocessable_entity, :invalid_request,
                              details: @saved_search.errors.as_json(full_messages: true))
        end
      end

      def destroy
        saved_search = Current.user.saved_searches.find(params[:id])
        saved_search.destroy!
        render json: { message: t("api.saved_searches.removed") }
      end
    end
  end
end
