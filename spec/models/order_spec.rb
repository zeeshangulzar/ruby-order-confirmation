require "rails_helper"

RSpec.describe Order, type: :model do
  let(:valid_attrs) do
    {
      stripe_event_id: "evt_test_123",
      customer_email:  "buyer@example.com",
      amount_total:    2999,
      currency:        "usd"
    }
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(Order.new(valid_attrs)).to be_valid
    end

    it "requires stripe_event_id" do
      expect(Order.new(valid_attrs.merge(stripe_event_id: nil))).not_to be_valid
    end

    it "requires a unique stripe_event_id" do
      Order.create!(valid_attrs)
      duplicate = Order.new(valid_attrs.merge(customer_email: "other@example.com"))
      expect(duplicate).not_to be_valid
    end

    it "requires a valid email" do
      expect(Order.new(valid_attrs.merge(customer_email: "not-an-email"))).not_to be_valid
    end

    it "requires non-negative amount_total" do
      expect(Order.new(valid_attrs.merge(amount_total: -1))).not_to be_valid
    end
  end

  describe "#formatted_total" do
    it "formats cents as a decimal amount with currency" do
      order = Order.new(amount_total: 2999, currency: "usd")
      expect(order.formatted_total).to eq("29.99 USD")
    end
  end

  describe "#items_summary" do
    it "returns a newline-separated list of items" do
      order = Order.new(
        currency:   "usd",
        line_items: [
          { "description" => "Widget", "quantity" => 2, "amount_total" => 5998 },
          { "description" => "Sticker", "quantity" => 1, "amount_total" => 199 }
        ]
      )
      expect(order.items_summary).to eq("2× Widget — 59.98 USD\n1× Sticker — 1.99 USD")
    end
  end

  describe "#shipping_summary" do
    it "returns 'N/A' when no shipping address is present" do
      expect(Order.new.shipping_summary).to eq("N/A")
    end

    it "formats an address into a multi-line block" do
      order = Order.new(shipping_address: {
        "name"        => "Jane Buyer",
        "line1"       => "1 Market St",
        "city"        => "San Francisco",
        "state"       => "CA",
        "postal_code" => "94105",
        "country"     => "US"
      })
      expect(order.shipping_summary).to eq("Jane Buyer\n1 Market St\nSan Francisco, CA, 94105\nUS")
    end
  end
end
