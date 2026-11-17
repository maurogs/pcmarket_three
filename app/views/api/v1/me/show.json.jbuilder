json.partial! "api/v1/partials/user", user: Current.user
json.unread_conversations @unread_conversations
json.unread_notifications @unread_notifications
json.cart_items @cart_items
