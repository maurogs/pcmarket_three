module Api
  module V1
    # POST/DELETE /api/v1/stores/:store_id/follow — follow and unfollow.
    # Mirrors FollowsController: Store.visible lookup (hidden stores 404),
    # own-store follows are refused with 422, unfollow is idempotent.
    class FollowsController < BaseController
      before_action :set_store

      def create
        follow = @store.follows.new(follower: Current.user)

        unless follow.save
          return render_error(:unprocessable_entity, :invalid_request,
                              details: { errors: follow.errors.full_messages })
        end

        @store.reload
        render json: { message: t("api.follows.followed"), following: true,
                       follower_count: @store.followers_count }
      end

      def destroy
        @store.follows.find_by(follower: Current.user)&.destroy!
        @store.reload
        render json: { message: t("api.follows.unfollowed"), following: false,
                       follower_count: @store.followers_count }
      end

      private

      def set_store
        @store = Store.visible.friendly.find(params[:store_id])
      end
    end
  end
end
