require "rails_helper"

RSpec.describe "Webhooks::Stripe", type: :request do
  let(:webhook_secret) { "whsec_test_secret" }

  before do
    ENV["STRIPE_WEBHOOK_SECRET"] = webhook_secret
  end

  def sign(payload, secret: webhook_secret, timestamp: Time.now.to_i)
    signature = Stripe::Webhook::Signature.compute_signature(Time.at(timestamp), payload, secret)
    "t=#{timestamp},v1=#{signature}"
  end

  def event_payload(event_id: "evt_test_123", session_id: "cs_test_abc")
    {
      id:   event_id,
      type: "checkout.session.completed",
      data: { object: { id: session_id, object: "checkout.session" } }
    }.to_json
  end

  let(:expanded_session) do
    Stripe::Checkout::Session.construct_from(
      id:                "cs_test_abc",
      amount_total:      2999,
      currency:          "usd",
      payment_status:    "paid",
      customer_details:  { email: "buyer@example.com", name: "Jane Buyer" },
      shipping_details:  {
        name:    "Jane Buyer",
        address: { line1: "1 Market St", city: "San Francisco", state: "CA", postal_code: "94105", country: "US" }
      },
      line_items:        { data: [{ description: "Widget", quantity: 1, amount_total: 2999, currency: "usd" }] }
    )
  end

  describe "POST /webhooks/stripe" do
    context "with a valid signed payload" do
      before do
        allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(expanded_session)
        allow(OrderConfirmationMailer).to receive(:deliver)
      end

      it "creates an order and returns 200" do
        payload = event_payload
        expect {
          post "/webhooks/stripe", params: payload, headers: {
            "Content-Type"    => "application/json",
            "Stripe-Signature" => sign(payload)
          }
        }.to change(Order, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(OrderConfirmationMailer).to have_received(:deliver).once
      end

      it "is idempotent — a repeated event does not create a duplicate order or resend email" do
        payload = event_payload

        2.times do
          post "/webhooks/stripe", params: payload, headers: {
            "Content-Type"    => "application/json",
            "Stripe-Signature" => sign(payload)
          }
        end

        expect(Order.where(stripe_event_id: "evt_test_123").count).to eq(1)
        expect(OrderConfirmationMailer).to have_received(:deliver).once
      end
    end

    it "returns 400 when the signature does not match" do
      payload = event_payload

      post "/webhooks/stripe", params: payload, headers: {
        "Content-Type"    => "application/json",
        "Stripe-Signature" => sign(payload, secret: "whsec_wrong")
      }

      expect(response).to have_http_status(:bad_request)
      expect(Order.count).to eq(0)
    end
  end
end
