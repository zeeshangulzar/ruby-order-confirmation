class CheckoutsController < ApplicationController
  PRODUCT = {
    name:        "ACME Widget",
    description: "A high-quality widget you'll love.",
    price_cents: 2999,
    currency:    "usd"
  }.freeze

  def new
    @product = PRODUCT
  end

  def create
    session = Stripe::Checkout::Session.create(
      mode:                          "payment",
      payment_method_types:          ["card"],
      billing_address_collection:    "required",
      shipping_address_collection:   { allowed_countries: %w[US CA GB PK] },
      line_items:                    [{
        quantity:  1,
        price_data: {
          currency:     PRODUCT[:currency],
          unit_amount:  PRODUCT[:price_cents],
          product_data: { name: PRODUCT[:name], description: PRODUCT[:description] }
        }
      }],
      success_url: success_url + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url:  root_url
    )

    redirect_to session.url, allow_other_host: true, status: :see_other
  end

  def success
  end
end
