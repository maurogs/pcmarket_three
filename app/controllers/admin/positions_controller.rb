module Admin
  # Nested singular resource on categories: POST creates one position swap
  # (direction param: up/down — buttons beside each tree row).
  class PositionsController < BaseController
    include Auditable

    def create
      category = Category.friendly.find(params[:category_id])
      direction = params[:direction].to_s

      # Guard the raw param: Category#move! raises on unknown directions.
      unless %w[up down].include?(direction)
        redirect_to admin_categories_path, alert: t(".boundary")
        return
      end

      if category.move!(direction)
        audit!("category_move", category, direction: direction, position: category.position)
        redirect_to admin_categories_path, notice: t(".moved", name: category.name)
      else
        redirect_to admin_categories_path, alert: t(".boundary")
      end
    end
  end
end
