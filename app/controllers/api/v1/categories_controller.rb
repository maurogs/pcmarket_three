module Api
  module V1
    # GET /api/v1/categories — the active category tree (roots + children),
    # GET /api/v1/categories/:id — one category by slug with its spec
    # attribute descriptors (the same rows the web form renders).
    class CategoriesController < BaseController
      skip_before_action :authenticate_token!

      def index
        @categories = Category.active.roots.ordered.includes(children: :spec_attributes)
      end

      def show
        @category = Category.active.find_by!(slug: params[:id])
      end
    end
  end
end
