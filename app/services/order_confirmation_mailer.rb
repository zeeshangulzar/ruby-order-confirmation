class OrderConfirmationMailer
  def self.deliver(order)
    new(order).deliver
  end

  def initialize(order)
    @order = order
  end

  def deliver
    mail = Mailtrap::Mail::FromTemplate.new(
      from:               { email: ENV.fetch("MAILTRAP_FROM_EMAIL"), name: "ACME Store" },
      to:                 [{ email: @order.customer_email, name: @order.customer_name.to_s }],
      template_uuid:      ENV.fetch("MAILTRAP_ORDER_TEMPLATE_UUID"),
      template_variables: template_variables
    )

    client.send(mail)
  end

  private

  def client
    @client ||= Mailtrap::Client.new(api_key: ENV.fetch("MAILTRAP_API_TOKEN"))
  end

  def template_variables
    {
      "order_id"         => @order.id.to_s,
      "customer_name"    => @order.customer_name.to_s,
      "items"            => @order.items_summary,
      "total"            => @order.formatted_total,
      "shipping_address" => @order.shipping_summary
    }
  end
end
