# Saved searches (Phase 5). A saved search stores the same filter params
# the browse form sends, so "open" is just the listings index with them.
# create enforces the 25-per-user cap; update toggles email alerts.
class SavedSearchesController < ApplicationController
  before_action :require_authentication
  before_action :set_saved_search, only: %i[update destroy]

  def index
    @saved_searches = current_user.saved_searches.order(created_at: :desc)
  end

  def create
    @saved_search = SavedSearch.new_from_search(
      user: current_user, name: params[:name], search_filters: search_filters
    )

    if @saved_search.save
      redirect_to saved_searches_path, notice: t(".created", name: @saved_search.name)
    else
      redirect_back fallback_location: listings_path, alert: @saved_search.errors.full_messages.first
    end
  end

  def update
    @saved_search.update!(email_alerts: !@saved_search.email_alerts)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("saved_search_#{@saved_search.id}",
                                                  partial: "saved_searches/saved_search",
                                                  locals: { saved_search: @saved_search })
      end
      format.html { redirect_to saved_searches_path, status: :see_other }
    end
  end

  def destroy
    @saved_search.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("saved_search_#{@saved_search.id}")
      end
      format.html { redirect_to saved_searches_path, status: :see_other }
    end
  end

  private

  def set_saved_search
    @saved_search = current_user.saved_searches.find(params[:id])
  end

  # The browse form's filter params (the model maps them onto the query,
  # category and filters columns).
  def search_filters
    params.permit(:q, :category, :min_price, :max_price, :condition, :f,
                  :labels, :tags, :seller)
  end
end
