# Follow / unfollow a store (Phase 5). Turbo Stream swaps the button in
# place; the model rejects following your own store.
class FollowsController < ApplicationController
  before_action :require_authentication
  before_action :set_store

  def create
    @follow = @store.follows.new(follower: current_user)

    respond_to do |format|
      if @follow.save
        format.turbo_stream { render turbo_stream: follow_streams }
        format.html { redirect_to store_path(@store), status: :see_other }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("follow_error_#{@store.id}",
                                                   @follow.errors.full_messages.first)
        end
        format.html { redirect_to store_path(@store), alert: @follow.errors.full_messages.first, status: :see_other }
      end
    end
  end

  def destroy
    @store.follows.find_by(follower: current_user)&.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: follow_streams }
      format.html { redirect_to store_path(@store), status: :see_other }
    end
  end

  private

  def set_store
    # Slug or id in the nested route; hidden (GDPR-anonymized) stores 404.
    @store = Store.visible.friendly.find(params[:store_id])
  end

  def follow_streams
    [
      turbo_stream.replace("follow_button_#{@store.id}",
                           partial: "shared/follow_button",
                           locals: { store: @store }),
      turbo_stream.replace("follower_count_#{@store.id}",
                           partial: "stores/follower_count",
                           locals: { store: @store })
    ]
  end
end
