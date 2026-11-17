# Shared transition envelope (order + localized message) rendered by the
# six status-change controllers under Api::V1 (payment_confirmations,
# shipments, delivery_confirmations, completions, cancellations, disputes).
json.partial! "api/v1/orders/transition", order: @order, message: @message
