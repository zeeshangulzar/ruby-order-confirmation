class StripeWebhookProcessor
  class InvalidSignature < StandardError; end

  RELEVANT_EVENTS = %w[checkout.session.completed].freeze

  def initialize(payload:, signature_header:)
    @payload          = payload
    @signature_header = signature_header
  end

  def call
    event = verify_and_parse
    return :ignored unless RELEVANT_EVENTS.include?(event.type)

    session = expanded_session(event.data.object.id)
    order   = find_or_create_order(event, session)
    return :duplicate unless order.previously_new_record?

    OrderConfirmationMailer.deliver(order)
    :processed
  end

  private

  def verify_and_parse
    Stripe::Webhook.construct_event(@payload, @signature_header, ENV.fetch("STRIPE_WEBHOOK_SECRET"))
  rescue Stripe::SignatureVerificationError, JSON::ParserError => e
    raise InvalidSignature, e.message
  end

  # checkout.session.completed events don't include line_items by default —
  # re-fetch the session with line_items expanded so we can render them in the email.
  def expanded_session(session_id)
    Stripe::Checkout::Session.retrieve(id: session_id, expand: ["line_items"])
  end

  def find_or_create_order(event, session)
    Order.find_or_create_by!(stripe_event_id: event.id) do |order|
      order.stripe_session_id = session.id
      order.customer_email    = session.customer_details&.email
      order.customer_name     = session.customer_details&.name
      order.amount_total      = session.amount_total
      order.currency          = session.currency
      order.line_items        = extract_line_items(session)
      order.shipping_address  = extract_shipping(session)
      order.status            = session.payment_status
    end
  end

  def extract_line_items(session)
    Array(session.line_items&.data).map do |item|
      {
        "description"  => item.description,
        "quantity"     => item.quantity,
        "amount_total" => item.amount_total,
        "currency"     => item.currency
      }
    end
  end

  def extract_shipping(session)
    details = session.shipping_details || session.customer_details
    return {} unless details&.respond_to?(:address) && details.address

    address = details.address
    {
      "name"        => details.try(:name),
      "line1"       => address.try(:line1),
      "line2"       => address.try(:line2),
      "city"        => address.try(:city),
      "state"       => address.try(:state),
      "postal_code" => address.try(:postal_code),
      "country"     => address.try(:country)
    }.compact
  end
end
