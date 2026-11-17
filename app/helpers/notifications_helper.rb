# Renders notification rows: the i18n text under notifications.kinds.*, an
# icon and the link target are all derived from the notification kind and
# its jsonb payload. Records referenced by payload ids are memoized per
# request so a page of notifications hits each at most once.
module NotificationsHelper
  KIND_ICONS = {
    "new_message" => :message,
    "new_offer" => :tag,
    "offer_accepted" => :check,
    "price_drop" => :tag,
    "saved_search_match" => :search,
    "listing_submitted" => :shield,
    "listing_approved" => :check,
    "listing_rejected" => :close,
    "order_placed" => :box,
    "order_confirmed" => :box,
    "order_paid" => :bolt,
    "order_shipped" => :truck,
    "order_delivered" => :box,
    "order_completed" => :check,
    "order_cancelled" => :close,
    "order_disputed" => :shield
  }.freeze

  FALLBACK_ICON = :bell

  def notification_icon(notification, classes: "size-4")
    inline_icon(KIND_ICONS.fetch(notification.kind, FALLBACK_ICON), classes: classes)
  end

  def notification_text(notification)
    kind = notification.kind
    payload = notification.payload

    case kind
    when "new_message"
      conversation = notification_conversation(notification)
      sender = conversation && (conversation.buyer_id == notification.user_id ? conversation.seller : conversation.buyer)
      t("notifications.kinds.new_message", name: sender&.display_name)
    when "price_drop"
      t("notifications.kinds.price_drop", title: payload["title"], price: money(payload["price_cents"]))
    when "saved_search_match"
      t("notifications.kinds.saved_search_match", name: payload["saved_search_name"], title: payload["title"])
    when "listing_submitted"
      t("notifications.kinds.listing_submitted", title: payload["title"])
    when "listing_approved"
      t("notifications.kinds.listing_approved", title: payload["title"])
    when "listing_rejected"
      t("notifications.kinds.listing_rejected", title: payload["title"])
    when "new_offer"
      t("notifications.kinds.new_offer", title: notification_offer(notification)&.listing&.title)
    when "offer_accepted"
      t("notifications.kinds.offer_accepted", title: notification_offer(notification)&.listing&.title)
    when /\Aorder_/
      t("notifications.kinds.#{kind}", number: notification_order(notification)&.number)
    else
      t("notifications.kinds.unknown", kind: kind.humanize)
    end
  rescue ActionView::MissingTranslation
    t("notifications.kinds.unknown", kind: kind.humanize)
  end

  # Where clicking the row goes; nil renders it as plain text.
  def notification_link(notification)
    payload = notification.payload

    case notification.kind
    when "new_message"
      conversation_id = payload["conversation_id"] and conversation_path(conversation_id)
    when "new_offer", "offer_accepted"
      offers_path
    when "price_drop", "saved_search_match", "listing_submitted",
         "listing_approved", "listing_rejected"
      listing = Listing.find_by(id: payload["listing_id"]) and listing_path(listing)
    when /\Aorder_/
      order_id = payload["order_id"] and order_path(order_id)
    end
  end

  private

  def notification_conversation(notification)
    notification_record(notification, "conversation_id", Conversation)
  end

  def notification_offer(notification)
    notification_record(notification, "offer_id", Offer)
  end

  def notification_order(notification)
    notification_record(notification, "order_id", Order)
  end

  def notification_record(notification, payload_key, klass)
    id = notification.payload[payload_key]
    return nil if id.blank?

    cache_key = "#{klass.name}_#{id}"
    (@_notification_records ||= {})[cache_key] ||= klass.find_by(id: id)
  end
end
