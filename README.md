# StampMitra Ruby SDK

[![CI](https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/stampmitra)](https://rubygems.org/gems/stampmitra)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red)](stampmitra.gemspec)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

> The RubyGems badge shows a version only once the gem is published.

Official Ruby client for the [StampMitra Developer API](https://developer.stampmitra.in/docs):
Indian identity verification (PAN, GSTIN, vehicle RC, Voter ID, driving licence, passport, CIN, Udyam, bank account)
and e-Stamp Paper. OpenAPI spec: <https://developer.stampmitra.in/openapi.json>.

> **Status: pre-1.0 (0.1.0).** The API surface may change in minor releases. Pin your version.

SDK guide: <https://developer.stampmitra.in/sdks/ruby> | API docs: <https://developer.stampmitra.in/docs>

## Install

```ruby compile-only
# Gemfile
gem 'stampmitra', '~> 0.1.0'
```

```bash
gem install stampmitra
```

Requires Ruby 3.0 or newer and nothing else: the gem uses only the standard library (`net/http`, `json`, `openssl`,
`securerandom`, `uri`, `logger`) and has **zero runtime dependencies**. See [Supported versions](#supported-versions)
for what has actually been tested.

## Quickstart

```ruby
require 'stampmitra'

client = StampMitra::Client.new(api_key: ENV['STAMPMITRA_API_KEY']) # or just StampMitra::Client.new
pan = client.verify.pan(pan: 'ABCDE1234F', name: 'Rahul Kumar')
puts "#{pan.valid? ? 'valid' : 'invalid'} #{pan.name_match_result} #{pan.reference_id}"
```

## Authentication

Keys look like `sk_test_...` (free sandbox) or `sk_live_...` (metered). They are read from the `STAMPMITRA_API_KEY`
environment variable unless you pass `api_key:`. Keys that do not match `^sk_(test|live)_[A-Za-z0-9_-]{8,}$` are rejected
unless `allow_custom_key: true`. `client.environment` is `'test'`, `'live'` (or `'custom'`).

> **Security:** server-side only. Never ship `sk_` keys in mobile apps, browser code or public repositories.

Client options: `api_key`, `base_url`, `timeout` (30s per attempt), `max_retries` (2), `adapter`, `default_headers`,
`app_info: { name:, version:, url: }` (appended to the User-Agent), `logger` (a `Logger`), `validate_input` (true),
`allow_custom_key`. `base_url` must be `https://` (plain `http://` is accepted only for `localhost`, `127.0.0.1` and `::1`,
e.g. a mock server) and must not contain credentials.

Every resource method takes a trailing `options:` hash for that call only:

```ruby
client.orders.get('ord_1', options: { timeout: 5, max_retries: 0, headers: { 'X-Trace-Id' => 'abc' } })
client.orders.create(
  external_order_id: 'ord_1', external_customer_id: 'cust_1', service_code: 'estamp.instrument.rent_agreement',
  options: { idempotency_key: 'order-ord_1-attempt-1' }
)
```

## Resources

| Resource | Methods |
|----------|---------|
| `client.verify` | `pan`, `gstin`, `rc`, `voter_id`, `driving_license`, `passport`, `cin`, `udyam`, `pan_to_gstin`, `pan_to_udyam`, `bank_account` |
| `client.services` | `list`, `get(service_code)` |
| `client.estamp` | `get_schema(service_code)`, `list_states`, `list_instruments(state_code)`, `list_articles(instrument_code)`, `calculate_duty(...)`, `add_parties(order_id, ...)` |
| `client.orders` | `create(...)`, `get(id)`, `get_status(id)`, `get_payment(id)`, `list_documents(id)`, `get_document_download(id, document_id)` |
| `client.payments.intents` | `create(...)`, `get(id)` |
| `client.usage` | `summary` |
| `client.logs` | `list(...)`, `each(...)`, `each_page(...)` |
| `client.webhooks.events` | `list(limit:, cursor:)`, `replay(id)` |

```ruby
# Verification: every call is billed, including valid: false results
client.verify.pan(pan: 'ABCDE1234F', name: 'Rahul Kumar')
client.verify.gstin(gstin: '27ABCDE1234F1Z5')
client.verify.rc(vehicle_number: 'MH12AB1234')
client.verify.voter_id(voter_id: 'ABC1234567')
client.verify.driving_license(dl_number: 'MH1420110012345', dob: '1990-01-31') # IP-allowlisted key required
client.verify.passport(file_number: 'PA1079341954215', dob: '1990-01-31')      # IP-allowlisted key required
client.verify.cin(cin: 'U74999DL2015PTC284009')
client.verify.udyam(udyam_number: 'UDYAM-MH-12-1234567')
client.verify.pan_to_gstin(pan: 'ABCDE1234F')
client.verify.pan_to_udyam(pan: 'ABCDE1234F')
client.verify.bank_account(account_number: '000123456789', ifsc: 'ICIC0001234', name: 'Rahul Kumar')

# Services and e-Stamp reference data
client.services.list.each { |service| puts service.service_code }
client.services.get('estamp.instrument.rent_agreement')
client.estamp.get_schema('estamp.instrument.rent_agreement')
client.estamp.list_states
client.estamp.list_instruments('MH')
client.estamp.list_articles('rent_agreement')
client.estamp.calculate_duty(state_code: 'MH', article_code: '5', stamp_duty_amount: 1000)
client.estamp.add_parties('ord_123', customer_name: 'Asha', party_name: 'Ravi')

# Orders and payments: orders are addressed by YOUR external_order_id
order = client.orders.create(external_order_id: 'ord_1', external_customer_id: 'cust_1', service_code: 'estamp.instrument.rent_agreement')
client.orders.get_status(order.external_order_id)
client.orders.get_payment(order.external_order_id)
client.orders.list_documents(order.external_order_id)
client.orders.get_document_download(order.external_order_id, 'doc_1')
client.payments.intents.create(external_order_id: 'ord_1', amount_minor: 50_000, currency: 'INR', payment_connection_id: 'pc_1')
client.payments.intents.get('pi_1')

# Usage, logs, webhook events
client.usage.summary
client.logs.list(service: 'pan.verify', status: 'success', limit: 50)
client.webhooks.events.list(limit: 20)
client.webhooks.events.replay('evt_1')
```

### Typed responses

Responses are immutable value objects built from the OpenAPI spec's named schemas (`StampMitra::Models::PanVerification`, ...).
Fields are snake_case readers (`pan.registered_name`, `pan.valid?`). Fields the gem does not know about are **never dropped**:

```ruby
pan = client.verify.pan(pan: 'ABCDE1234F')
pan[:referenceId]  # any field by JSON key or snake_case name, declared or not
pan.unknown_fields # JSON keys the server sent that this version does not model
pan.to_h           # a deep copy of the complete decoded body
```

`inspect` / `to_s` mask identifiers and remove names, because responses carry personal data. The e-Stamp reference data, duty
calculation, parties and webhook-event endpoints have no fixed shape in the API, so they return `Models::GenericResponse`
(`#[]`, `#to_h`, `#items`, `Enumerable`). `services.list` returns an `Enumerable` of `Models::Service`.

### Raw response access

```ruby
order, response = client.with_response.orders.get('ord_1')
response.status      # 200
response.headers     # lower-case header names
response.request_id  # X-Request-Id when the API sent one
response.attempts    # HTTP attempts it took (retries included)
response.body        # the raw JSON text
```

Every typed result also carries its response: `order.response.status`.

## Errors

Every error inherits from `StampMitra::Error` and exposes `status`, `code`, `message`, `request_id`, `field` and `body`:

| HTTP | Error class |
|------|-------------|
| 400 (and local validation) | `ValidationError` |
| 401 | `AuthenticationError` |
| 402 | `PaymentRequiredError` |
| 403 | `PermissionDeniedError` (server message verbatim, e.g. IP allowlist) |
| 404 | `NotFoundError` |
| 409 | `ConflictError` |
| 429 | `RateLimitError` (`retry_after` seconds when the header is present) |
| 5xx | `UpstreamError` |
| network / timeout | `ConnectionError` / `TimeoutError` (a `ConnectionError`) |
| webhook verification | `SignatureVerificationError` |

Other statuses raise the base `StampMitra::Error`; non-JSON error bodies still map by status.

```ruby
begin
  client.verify.gstin(gstin: '27ABCDE1234F1Z5')
rescue StampMitra::RateLimitError => e
  sleep(e.retry_after || 1) # the API sends no Retry-After today, so this is usually nil
rescue StampMitra::PermissionDeniedError => e
  warn "not allowed: #{e.message}"
rescue StampMitra::Error => e
  warn "#{e.class} #{e.status} #{e.code} request_id=#{e.request_id}: #{e.message}"
end
```

## Retries and idempotency

`max_retries` defaults to 2 (at most 3 attempts) with exponential backoff and full jitter (0.5s base, 8s cap). `Retry-After` is
honoured when sent (seconds or HTTP date, capped at 60s). Retried: 429, 502, 503, 504, connection errors and timeouts.
Never retried: other 4xx and 5xx statuses, and redirects (which are not followed).

* **GET** is always retry-safe.
* **POST** is retried only when it carries an `Idempotency-Key`. The gem generates a CSPRNG UUIDv4 key for every POST the API
  accepts one on (verification, duty calculation, e-Stamp parties, orders, payment intents) and reuses the **same key on
  every attempt**, so a retry replays the original result instead of creating or billing twice. Pass your own with
  `options: { idempotency_key: '...' }`.
* **Webhook replay** has no idempotency and is never retried unless you pass a key.

Set `max_retries: 0` (client or per request) to disable retries. Each request uses a fresh connection and Net::HTTP's own
transparent retry is disabled, so a request is never silently replayed.

### Timeouts

`timeout` (default 30s) applies to connecting (capped at 10s), to each read and to each write, per attempt, and can be set
per request. It is not a total deadline across a slowly trickling response.

## Pagination

`logs.each` follows `next_cursor` lazily and returns an `Enumerator` when called without a block, so it composes with
`lazy`, `first`, `take`, `each_slice`...:

```ruby
client.logs.each(service: 'pan.verify', limit: 100) do |entry|
  puts "#{entry.created_at} #{entry.service} #{entry.id}"
end

latest = client.logs.each(limit: 50).lazy.select { |entry| entry.service == 'pan.verify' }.first(10) # stops fetching pages early
page = client.logs.list(limit: 50) # page.items, page.next_cursor
```

## Webhooks

Deliveries carry `X-Webhook-Signature`, `X-Webhook-Timestamp` (Unix seconds) and `X-Webhook-Event-Id`. The signature is
`hex(HMAC-SHA256(secret, "#{timestamp}.#{raw_body}"))` over the body **exactly as received**: pass the raw request body, never
re-serialised JSON.

```ruby
payload = request.body.read # Rack/Sinatra; in Rails use request.raw_post
begin
  event = StampMitra::Webhook.construct_event_from_headers(
    payload: payload, headers: request.env, secret: ENV.fetch('STAMPMITRA_WEBHOOK_SECRET')
  )
  puts "#{event.type} #{event.core_order_id} delivery=#{event.event_id}"
rescue StampMitra::SignatureVerificationError => e
  warn "rejected: #{e.code}" # respond 400
end
```

`construct_event_from_headers` accepts a Rack `env`, any Hash with any header casing, or Rails' `request.headers`. Without header
objects use `StampMitra::Webhook.construct_event(payload:, timestamp:, signature:, secret:)` or the boolean
`StampMitra::Webhook.verify_signature(...)`. The returned event is typed for the eight order events:

| `event.type` | Class |
|--------------|-------|
| `order.created` | `Webhook::OrderCreated` |
| `order.payment_confirmed` | `Webhook::OrderPaymentConfirmed` |
| `order.fulfilment_started` | `Webhook::OrderFulfilmentStarted` |
| `order.fulfilment_completed` | `Webhook::OrderFulfilmentCompleted` |
| `order.failed` | `Webhook::OrderFailed` |
| `order.cancelled` | `Webhook::OrderCancelled` |
| `order.refund_completed` | `Webhook::OrderRefundCompleted` |
| `order.document_ready` | `Webhook::OrderDocumentReady` |

Each has `core_order_id`, `core_event_type`, `occurred_at` and `event_id`; extra fields stay available through `event[:field]`
and `event.to_h`. An unrecognised `coreEventType` yields a plain `Webhook::Event` (never an error). The comparison is
constant-time, timestamps more than 300 seconds (`tolerance:`) from now are rejected, and an empty secret is refused.
See `examples/sinatra_webhook.rb`, `examples/rack_webhook.ru` and `examples/rails_webhooks_controller.rb`.

## Validation

Inputs are checked before anything is sent (PAN, GSTIN, IFSC, CIN, Udyam, vehicle number, 9-18 digit account number, passport
file number, driving licence, voter ID, phone, ISO dates, names), with a local `ValidationError` carrying `field`, no network
call and nothing billed. Values are trimmed and upper-cased, but separators are **not** stripped (`"MH 12 AB 1234"` is
rejected, exactly as the API does). The validators are also public:

```ruby
StampMitra::Validators.pan(' abcde1234f ') # => "ABCDE1234F"

begin
  StampMitra::Validators.bank_account('1234-5678')
rescue StampMitra::ValidationError => e
  puts "#{e.field}: #{e.message}"
end
```

Disable with `validate_input: false` to let the API decide.

## Logging

Pass a standard `Logger` as `logger:` to get debug logs of requests and responses. `Authorization` and `x-api-key` are redacted, and
identifiers (PAN, GSTIN, account numbers) and names in bodies are masked. Nothing is logged by default.

```ruby
require 'logger'
logged = StampMitra::Client.new(api_key: ENV['STAMPMITRA_API_KEY'], logger: Logger.new($stderr, level: Logger::DEBUG))
logged.usage.summary
```

## Security

- Use keys server-side only and keep them in environment variables or a secret manager; never commit them.
- TLS certificates and host names are always verified (TLS 1.2+), redirects are never followed (credentials cannot be forwarded to
  another host) and `base_url` must be `https://` except for loopback hosts.
- The API key and webhook secret never appear in `inspect`, `to_s`, `pp`, YAML, error messages or logs, and clients are not
  `Marshal`-able.
- Path ids are validated and percent-encoded; `.`/`..`, empty ids and slashes are rejected. Header values containing CR/LF are rejected.
- Always verify webhook signatures on the raw body and keep the default 300s timestamp tolerance.
- Report vulnerabilities as described in [SECURITY.md](SECURITY.md), not in public issues.

## Supported versions

CI runs the test suite on Ruby 3.0, 3.1, 3.2, 3.3 and 3.4. JRuby and TruffleRuby are not part of the CI matrix. Only the latest
minor release receives fixes while the SDK is pre-1.0. See [CHANGELOG.md](CHANGELOG.md).

## Development

```bash
bundle install
bundle exec rake                 # unit tests, RuboCop, spec coverage, generated-model check
bundle exec rake test:conformance # black-box run against the spec repo's mock server (see CONTRIBUTING.md)
scripts/check-readme-snippets    # compiles and runs every Ruby block in this README
bundle exec yard stats --list-undoc
```

`spec/openapi.json` is a snapshot of the public spec; `rake coverage` (and a unit test) fail if any `METHOD + path` in it has no SDK
method, and `rake models` fails if the generated response models are stale. See [CONTRIBUTING.md](CONTRIBUTING.md),
[RELEASING.md](RELEASING.md) and [SECURITY.md](SECURITY.md).

Licensed under the [MIT License](LICENSE). Copyright StampMitra / Bani Global Industries LLP.
