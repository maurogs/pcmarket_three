module Sell
  # Badge chip for an order status in the sales views. Colours follow the
  # Tailwind palette directly (same family as the error summary reds).
  module SalesHelper
    STATUS_BADGE_CLASSES = {
      pending_payment: "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300",
      paid: "bg-sky-100 text-sky-800 dark:bg-sky-950 dark:text-sky-300",
      shipped: "bg-indigo-100 text-indigo-800 dark:bg-indigo-950 dark:text-indigo-300",
      delivered: "bg-teal-100 text-teal-800 dark:bg-teal-950 dark:text-teal-300",
      completed: "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300",
      cancelled: "bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-400",
      refunded: "bg-orange-100 text-orange-800 dark:bg-orange-950 dark:text-orange-300",
      disputed: "bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-300"
    }.freeze

    def order_status_badge(order)
      classes = STATUS_BADGE_CLASSES.fetch(order.status.to_sym, "bg-surface-muted text-muted")
      # Slash key (see Phase 6a): `order.status.completed` is a nested YAML
      # lookup that no longer exists — labels live as "status/completed".
      tag.span(Order.human_attribute_name("status/#{order.status}"),
               class: "shrink-0 rounded px-2 py-0.5 text-xs font-semibold #{classes}")
    end
  end
end
