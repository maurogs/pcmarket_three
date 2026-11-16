module Sell
  # Turbo Frame endpoint for the listing form's category picker: renders the
  # child-category select plus the dynamic spec fields for the chosen
  # category's all_spec_attributes. Fetched when the root or child select
  # changes; see app/javascript/controllers/listing_form_controller.js.
  class CategoryFieldsController < BaseController
    def show
      @category = Category.friendly.find(params[:id])
      render layout: false
    end
  end
end
