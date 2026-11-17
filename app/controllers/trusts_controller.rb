# GET /trust-and-safety — the Trust & Safety page. All numbers are live
# counts from the database; any stat below the min_public_stat setting is
# dropped from the page entirely (an empty-looking marketplace would hurt
# more trust than it builds).
class TrustsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @stats = Trust::Stats.visible
  end
end
