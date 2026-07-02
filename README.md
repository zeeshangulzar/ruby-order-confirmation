# ruby-order-confirmation

A Ruby on Rails demo showing how to send an **order confirmation email** from a **Stripe `checkout.session.completed` webhook** using the **Mailtrap Email API** with a Mailtrap-hosted email template.

A customer completes a Stripe Checkout session → Stripe fires a signed webhook → the app verifies the signature, persists the order (idempotently), then calls the Mailtrap Email API with a `template_uuid` and a variables map (`order_id`, `items`, `total`, `shipping_address`, …). The email HTML lives in the Mailtrap dashboard, not in the codebase.

## Features

- Stripe Checkout integration with a demo product page at `/`
- `POST /webhooks/stripe` webhook handler with `Stripe::Webhook.construct_event` signature verification
- Idempotency — the same Stripe event ID is stored only once, so retries never duplicate emails
- Uses the Mailtrap Email API (`Mailtrap::Mail::FromTemplate`) — no ActionMailer view files, the template lives in Mailtrap
- `line_items` and `shipping_details` are re-fetched with `expand: ["line_items"]` so the email can show what was purchased
- Returns HTTP `500` on internal failure so Stripe automatically retries the delivery
- Rejects tampered payloads with HTTP `400` (signature verification failure)

## Architecture

```
Browser ─► POST /checkout ─► Stripe Checkout
                                    │
                                    ▼
                            Stripe hosted page (card entry)
                                    │
                                    ▼ (checkout.session.completed)
Stripe ─► POST /webhooks/stripe ─► StripeWebhookProcessor
                                          │
                                          ├── Stripe::Webhook.construct_event (signature)
                                          ├── Stripe::Checkout::Session.retrieve(expand: [line_items])
                                          ├── Order.find_or_create_by!(stripe_event_id: …)  (idempotency)
                                          └── OrderConfirmationMailer.deliver(order)
                                                          │
                                                          ▼
                                                  Mailtrap Email API
                                                  (template_uuid + variables)
```

## Requirements

- Ruby 3.3.6
- Rails 7.2
- SQLite3
- A [Mailtrap](https://mailtrap.io) account (free tier works)
- A [Stripe](https://stripe.com) account in test mode
- [Stripe CLI](https://stripe.com/docs/stripe-cli) for forwarding webhooks to `localhost`

## Setup

```bash
git clone https://github.com/zeeshangulzar/ruby-order-confirmation
cd ruby-order-confirmation

bundle install

cp .env.example .env
# Edit .env — add your Mailtrap and Stripe credentials

rails db:create db:migrate
rails server
```

Open `http://localhost:3000` in your browser.

### Mailtrap setup

This app uses the **Mailtrap Email API** with a template hosted in the Mailtrap dashboard.

1. Sign in to [Mailtrap](https://mailtrap.io) → **Domains** and either verify your own sending domain or use the pre-created **`demomailtrap.co`** demo domain (delivery only to your Mailtrap account email)
2. Go to **Settings** → **API Tokens** → **Add API Token** and give it the **Admin** permission on your domain — put the token into `.env` as `MAILTRAP_API_TOKEN`
3. Go to **Templates** → **New Template** and create an HTML template with these placeholders:
   - `{{order_id}}`
   - `{{customer_name}}`
   - `{{items}}` — a newline-separated list of items
   - `{{total}}` — the formatted total (e.g. `29.99 USD`)
   - `{{shipping_address}}` — a newline-separated address block
4. Copy the **Template UUID** into `.env` as `MAILTRAP_ORDER_TEMPLATE_UUID`
5. Set `MAILTRAP_FROM_EMAIL` to a sender on your verified domain (e.g. `hello@demomailtrap.co`)

### Stripe setup

1. Grab your **test-mode secret key** from [Stripe Dashboard → Developers → API keys](https://dashboard.stripe.com/test/apikeys). Put it into `.env` as `STRIPE_SECRET_KEY` (starts with `sk_test_...`).
2. Pick one of the three webhook delivery paths below (Stripe CLI, ngrok, or a real public URL) and follow it to obtain a `STRIPE_WEBHOOK_SECRET`.
3. Restart `rails server` so it picks up the new secret.
4. Open `http://localhost:3000`, click **Buy Now**, and use Stripe's test card `4242 4242 4242 4242` with any future expiry, any CVC, and any postal code.

Or, if you just want to see the email delivery path without touching Stripe at all:

```bash
bin/rails simulate:order_email
```

That rake task builds a fake order and calls `OrderConfirmationMailer` directly against the Mailtrap Email API — no Stripe involvement.

### Getting a webhook signing secret

Stripe's servers can't reach `localhost` from the internet, so you need one of the three paths below.

#### Option A — Stripe CLI (recommended for local dev)

The Stripe CLI opens a tunnel between Stripe and your local server. It's the simplest path with the fewest moving parts.

```bash
brew install stripe/stripe-cli/stripe
stripe login
stripe listen --forward-to localhost:3000/webhooks/stripe
```

The CLI prints a signing secret (`whsec_...`) — put it into `.env` as `STRIPE_WEBHOOK_SECRET`. Keep the `stripe listen` process running while you test.

#### Option B — ngrok (public URL for your localhost)

If you'd rather see the exact flow Stripe uses in production, expose your local port with [ngrok](https://ngrok.com):

```bash
brew install ngrok
ngrok config add-authtoken YOUR_TOKEN   # one-time, sign up at ngrok.com
ngrok http 3000
```

ngrok prints a public URL like `https://abc123-45-67.ngrok-free.app`. In [Stripe Dashboard → Developers → Webhooks → Add endpoint](https://dashboard.stripe.com/test/webhooks):

- **Endpoint URL:** `https://abc123-45-67.ngrok-free.app/webhooks/stripe`
- **Events to send:** `checkout.session.completed`

Save the endpoint, click it, reveal the **Signing secret**, and put the `whsec_...` value into `.env` as `STRIPE_WEBHOOK_SECRET`.

Note: on the ngrok free plan the URL changes every time you restart, and you'll need to update the endpoint in Stripe each time. Paid plans keep the subdomain stable.

#### Option C — production (real domain)

Once the app is deployed to a public server (Heroku, Fly.io, Render, DigitalOcean, etc.), you don't need Stripe CLI or ngrok at all. Register the deployed URL directly in [Stripe Dashboard → Developers → Webhooks](https://dashboard.stripe.com/webhooks):

- **Endpoint URL:** `https://yourdomain.com/webhooks/stripe`
- Copy the endpoint's signing secret into the production `STRIPE_WEBHOOK_SECRET` env var

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MAILTRAP_API_TOKEN` | Mailtrap API token with sending permission on your domain |
| `MAILTRAP_FROM_EMAIL` | Verified sender address (e.g. `hello@demomailtrap.co`) |
| `MAILTRAP_ORDER_TEMPLATE_UUID` | UUID of the transactional template in Mailtrap → Templates |
| `STRIPE_SECRET_KEY` | Stripe test-mode secret key |
| `STRIPE_WEBHOOK_SECRET` | Signing secret — from `stripe listen`, or the dashboard endpoint if you use ngrok / a real URL |

## Email Flow

1. Customer opens `/` and clicks **Buy Now**
2. `CheckoutsController#create` creates a `Stripe::Checkout::Session` with inline `line_items` and required shipping address collection, then redirects to Stripe's hosted checkout
3. Customer pays with a test card and is redirected to `/success?session_id=…`
4. Stripe delivers `checkout.session.completed` to `/webhooks/stripe`
5. `Webhooks::StripeController#create` hands the raw payload + `Stripe-Signature` header to `StripeWebhookProcessor`
6. `StripeWebhookProcessor`:
   - Verifies the signature via `Stripe::Webhook.construct_event` (raises on tamper)
   - Ignores events other than `checkout.session.completed`
   - Re-fetches the session with `expand: ["line_items"]` to get the full items and shipping details
   - Calls `Order.find_or_create_by!(stripe_event_id: event.id)` — if the row already existed the second call is a no-op, no email is sent again
   - Passes the fresh order to `OrderConfirmationMailer.deliver`
7. `OrderConfirmationMailer` builds a `Mailtrap::Mail::FromTemplate` object with the template UUID and the variables map, then calls `Mailtrap::Client#send`
8. On any internal error the controller returns HTTP `500` so Stripe retries the delivery automatically

## Key Files

| File | Purpose |
|------|---------|
| `app/controllers/checkouts_controller.rb` | Product page, Stripe Checkout session creation, success page |
| `app/controllers/webhooks/stripe_controller.rb` | Webhook endpoint — signature verification and error handling |
| `app/services/stripe_webhook_processor.rb` | Signature verify, event filtering, idempotent order creation |
| `app/services/order_confirmation_mailer.rb` | Calls the Mailtrap Email API with `template_uuid` + variables |
| `app/models/order.rb` | Persisted order — line items + shipping address serialized as JSON |
| `config/routes.rb` | Defines `/`, `/checkout`, `/success`, `/webhooks/stripe` |
| `config/initializers/stripe.rb` | Sets `Stripe.api_key` from `STRIPE_SECRET_KEY` |
| `db/migrate/*_create_orders.rb` | Orders table with a unique `stripe_event_id` index |

## Mailtrap Integration

The email HTML lives in the Mailtrap dashboard, not in `app/views`. The app calls the Email API with a template UUID and a variables map:

```ruby
# app/services/order_confirmation_mailer.rb
mail = Mailtrap::Mail::FromTemplate.new(
  from:               { email: ENV.fetch("MAILTRAP_FROM_EMAIL"), name: "ACME Store" },
  to:                 [{ email: order.customer_email, name: order.customer_name.to_s }],
  template_uuid:      ENV.fetch("MAILTRAP_ORDER_TEMPLATE_UUID"),
  template_variables: {
    "order_id"         => order.id.to_s,
    "customer_name"    => order.customer_name.to_s,
    "items"            => order.items_summary,
    "total"            => order.formatted_total,
    "shipping_address" => order.shipping_summary
  }
)

Mailtrap::Client.new(api_key: ENV.fetch("MAILTRAP_API_TOKEN")).send(mail)
```

## Running Tests

```bash
bundle exec rspec
```

Tests cover:

- Order model validations (presence, uniqueness of `stripe_event_id`, email format)
- Webhook endpoint accepts a valid signed payload and creates an order
- Webhook endpoint rejects a tampered payload with HTTP 400
- Duplicate webhook events do not create a second order and do not resend the email

## License

MIT License — see [LICENSE](LICENSE) for details.
