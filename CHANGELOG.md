# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/) (pre-1.0: minor releases may contain breaking changes).

## [Unreleased]

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

[Unreleased]: https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/releases/tag/v0.1.0
