# Block management. A block stops new threads and messages in either
# direction (Conversations::Start and Messages::Send read it). Everything is
# scoped to current_user.blocks_cast — nobody unblocks on someone else's
# behalf.
class BlocksController < ApplicationController
  def index
    @pagy, @blocks = pagy(current_user.blocks_cast.includes(:blocked).order(created_at: :desc, id: :desc), limit: 20)
  end

  def create
    block = current_user.blocks_cast.new(blocked_id: params[:blocked_id])

    if block.save
      redirect_back fallback_location: blocks_path, notice: t(".created")
    else
      redirect_back fallback_location: blocks_path, alert: t("blocks.errors.#{block.errors.details[:blocked_id].first[:error]}")
    end
  end

  def destroy
    block = current_user.blocks_cast.find(params[:id])
    block.destroy!
    redirect_back fallback_location: blocks_path, notice: t(".destroyed")
  end
end
