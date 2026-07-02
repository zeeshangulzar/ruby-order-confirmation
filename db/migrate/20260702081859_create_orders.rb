class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.string :stripe_event_id, null: false
      t.string :stripe_session_id
      t.string :customer_email, null: false
      t.string :customer_name
      t.integer :amount_total, null: false
      t.string :currency, null: false, default: "usd"
      t.text :line_items
      t.text :shipping_address
      t.string :status, null: false, default: "paid"

      t.timestamps
    end
    add_index :orders, :stripe_event_id, unique: true
  end
end
