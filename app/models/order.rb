class Order < ApplicationRecord
  serialize :line_items,       coder: JSON, type: Array
  serialize :shipping_address, coder: JSON, type: Hash

  validates :stripe_event_id, presence: true, uniqueness: true
  validates :customer_email,  presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :amount_total,    presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency,        presence: true

  def formatted_total
    format("%.2f %s", amount_total.to_f / 100, currency.to_s.upcase)
  end

  def items_summary
    line_items.map { |item|
      "#{item['quantity']}× #{item['description']} — #{format('%.2f %s', item['amount_total'].to_f / 100, currency.to_s.upcase)}"
    }.join("\n")
  end

  def shipping_summary
    return "N/A" if shipping_address.blank?
    [
      shipping_address["name"],
      shipping_address["line1"],
      shipping_address["line2"],
      [shipping_address["city"], shipping_address["state"], shipping_address["postal_code"]].compact.join(", "),
      shipping_address["country"]
    ].compact_blank.join("\n")
  end
end
