module Webhooks
  class StripeController < ActionController::API
    def create
      payload   = request.raw_post
      signature = request.env["HTTP_STRIPE_SIGNATURE"]

      result = StripeWebhookProcessor.new(payload: payload, signature_header: signature).call
      head :ok
    rescue StripeWebhookProcessor::InvalidSignature => e
      Rails.logger.warn("Stripe webhook signature verification failed: #{e.message}")
      head :bad_request
    rescue => e
      # Any other failure (Mailtrap outage, DB blip) — return 500 so Stripe retries.
      Rails.logger.error("Stripe webhook processing failed: #{e.class} - #{e.message}")
      head :internal_server_error
    end
  end
end
