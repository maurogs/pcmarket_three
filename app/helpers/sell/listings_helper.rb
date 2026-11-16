module Sell::ListingsHelper
  def status_badge_class(status)
    case status.to_s
    when "approved" then "bg-emerald-100 text-emerald-800"
    when "pending_review" then "bg-amber-100 text-amber-800"
    when "rejected" then "bg-rose-100 text-rose-800"
    when "sold" then "bg-sky-100 text-sky-800"
    when "archived" then "bg-gray-100 text-gray-600"
    else "bg-gray-100 text-gray-700"
    end
  end
end
