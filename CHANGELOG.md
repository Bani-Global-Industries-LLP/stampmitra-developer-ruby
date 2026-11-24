# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/) (pre-1.0: minor releases may contain breaking changes).

## [Unreleased]

## [0.2.0] - 2026-11-24

Tracks StampMitra Developer API contract 1.2.0: 62 operations (was 31). Additive, with the behaviour changes listed under "Changed".

### Added
- **e-Stamp catalogue:** `client.estamp.get_states_availability`, `get_state`, `get_state_requirements` (with the generated
  `example_body`), `list_districts`, `list_sros`.
- **e-Stamp orders (`client.estamp.orders`):** `validate`, `create`, `list` / `each` / `each_page`, `get`, `cancel`, `export`,
  `list_stamps` and `upload_document` (multipart PAN card upload, PDF / JPEG / PNG up to 10 MB). `create` requires an
  `Idempotency-Key`: one is generated when you omit it and reused across retries.
- **Stamps (`client.estamp.stamps`):** `get`, `cancel`, `replace`, `set_pan_card` (HTTP 202, processed asynchronously), `get_certificate`.
- **Wallets (`client.wallets`):** `get` (both wallets) and, for `stamp_duty` and `service_fee`, `get_balance`, `topup`,
  `list_transactions` / `each_transaction`, `list_invoices` / `each_invoice`, `get_invoice`. Amounts are returned exactly as the API
  sends them; the SDK never computes fees.
- **Account:** `client.account.balance` and `client.account.usage`.
- Request types `StampMitra::EstampStampLine`, `EstampParty` and `EstampPropertyArea` (plain hashes work too). A party is a name
  string or an object; the order body is checked locally (one state per order, at most 5000 stamps, `quantity` 1 to 1000,
  `https://` PAN card links, enums) and reports every finding as `error.errors`.
- Error readers `details`, `errors` (items with `field`, `code`, `message`, `index`) and `wallet` (`STAMP_DUTY` / `SERVICE_FEE` on a
  402), and `retry_after` on every error class (it was only on `RateLimitError`).
- 35 typed response models (and two enumerable list types) for the new schemas, generated from the spec.
- Multipart request support in the transport (bodies are never logged), `examples/estamp_order.rb` and `examples/wallets.rb`.

### Changed
- Retries follow the 1.2.0 contract: `Retry-After` is honoured on 429, 503 and 409 `IDEMPOTENCY_IN_PROGRESS` (retried with the same
  key); every other 409 is still never retried. `estamp.orders.validate` (a dry run) is retried without a key. Order cancel, stamp
  cancel / replace, the PAN card link and both wallet top-ups are never retried.
- **Webhook replay is now never retried automatically**, even when you pass an `idempotency_key` (it was retried with a key).
- HTTP 422 (for example `IDEMPOTENCY_KEY_REUSED`) now raises `ValidationError` (it raised the base `StampMitra::Error`).
- `Models::GstinVerification#gstin` reads the `gstin` key; the legacy upper-case `GSTIN` key is `#gstin_legacy`.
- Verification models gained `verification_id` and the other fields of the 1.2.0 spec; `spec/openapi.json` and
  `test/fixtures/retry-scenarios.json` refreshed to contract 1.2.0.
- `scripts/generate-models` reads the spec as UTF-8 regardless of the locale.

## [0.1.0] - 2026-10-16

### Added
- Initial release: `StampMitra::Client` with `verify`, `services`, `estamp`, `orders`, `payments.intents`, `usage`, `logs`
  and `webhooks.events` resources covering all 31 operations of the StampMitra Developer API (spec v1.0.0).
- Typed, immutable response models generated from the OpenAPI schemas; unknown fields are preserved (`#[]`, `#to_h`).
- `StampMitra::Error` hierarchy (`AuthenticationError`, `PermissionDeniedError`, `PaymentRequiredError`, `ValidationError`,
  `NotFoundError`, `ConflictError`, `RateLimitError#retry_after`, `UpstreamError`, `ConnectionError`, `TimeoutError`,
  `SignatureVerificationError`) with `status`, `code`, `request_id`, `field`, `body`.
- Retries with exponential backoff and full jitter, `Retry-After` support, and automatic CSPRNG `Idempotency-Key`s reused across
  retries for every idempotent POST.
- Per-request `options:` (`timeout`, `max_retries`, `idempotency_key`, `headers`) and raw response access via `client.with_response`.
- Lazy cursor pagination: `client.logs.each` returns an `Enumerator`; `each_page` yields pages.
- `StampMitra::Webhook.verify_signature`, `construct_event` and `construct_event_from_headers` with typed `order.*` events,
  constant-time comparison and a 300 second timestamp tolerance.
- Client-side validators (exact API patterns), opt-out with `validate_input: false`.
- Debug logging through a standard `Logger` with redaction of credentials and personal data (off by default).
- Zero runtime dependencies (standard library only); TLS verified, redirects never followed, secrets kept out of
  `inspect`/`to_s`/errors/logs.

[Unreleased]: https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/releases/tag/v0.1.0
