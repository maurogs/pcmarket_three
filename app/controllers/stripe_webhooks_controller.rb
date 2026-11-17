# POST /stripe_webhooks — Stripe's callback endpoint. No session (and
# CSRF skipped), authentication comes solely from the HMAC signature in
# the Stripe-Signature header, verified against STRIPE_WEBHOOK_SECRET.
# Unverifiable payloads get a 400 and are never applied. Event handling
# lives in Payments::HandleWebhook.
class StripeWebhooksController < ApplicationController
  allow_unauthenticated_access
  # The class-level `allow_browser` guard would reject Stripe's client;
  # webhooks only ever talk to us through the signature below.
  skip_forgery_protection

  def create
    event = verified_event
    return head(:bad_request) if event.nil?

    Payments::HandleWebhook.call(event)
    head(:ok)
  end

  private

  def verified_event
    Stripe::Webhook.construct_event(
      request.body.read,
      request.headers["Stripe-Signature"].to_s,
      ENV["STRIPE_WEBHOOK_SECRET"].to_s
    )
  rescue Stripe::SignatureVerificationError, Stripe::JSONParseError, ArgumentError
    nil
  end
end
