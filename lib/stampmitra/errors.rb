# frozen_string_literal: true

module StampMitra
  # Base class of every error raised by this gem.
  #
  # API errors carry the HTTP +status+, the machine readable +code+, the
  # server-side +request_id+ (quote it when contacting support), the offending
  # input +field+ for validation errors, the decoded response +body+ (a Hash,
  # or the raw String for non-JSON bodies) and the response +headers+.
  # Errors raised locally (client-side validation, network failures) have a
  # +nil+ status. The API key is never part of an error message.
  class Error < StandardError
    # @return [Integer, nil] HTTP status, or nil when no response was received
    attr_reader :status
    # @return [String, nil] machine readable error code, e.g. "VALIDATION_ERROR"
    attr_reader :code
    # @return [String, nil] server-side request id
    attr_reader :request_id
    # @return [String, nil] offending input field, when known
    attr_reader :field
    # @return [Hash, String, nil] decoded JSON body, raw text for non-JSON bodies, or nil
    attr_reader :body
    # @return [Hash{String => String}] response headers (lower-case names); empty for local errors
    attr_reader :headers

    # @param message [String, nil] human readable message (defaults to "HTTP <status>")
    # @param status [Integer, nil]
    # @param code [String, nil]
    # @param request_id [String, nil]
    # @param field [String, nil]
    # @param body [Hash, String, nil]
    # @param headers [Hash{String => String}, nil]
    def initialize(message = nil, status: nil, code: nil, request_id: nil, field: nil, body: nil, headers: nil)
      super(message || (status ? "HTTP #{status}" : self.class.name))
      @status = status
      @code = code
      @request_id = request_id
      @field = field
      @body = body
      @headers = headers || {}
    end

    # @return [Hash{Symbol => Object}] the non-secret diagnostic fields, handy for structured logging
    def to_h
      { class: self.class.name, message: message, status: status, code: code, request_id: request_id, field: field }
    end
  end

  # HTTP 400, or an input that failed client-side validation (no request was sent).
  class ValidationError < Error
    # Builds a local validation error for +field+.
    #
    # @param field [String, Symbol]
    # @param message [String]
    # @return [ValidationError]
    def self.for_field(field, message)
      new(message, status: nil, code: 'VALIDATION_ERROR', field: field.to_s)
    end
  end

  # HTTP 401: missing, invalid or revoked API key.
  class AuthenticationError < Error; end

  # HTTP 402: insufficient wallet balance.
  class PaymentRequiredError < Error; end

  # HTTP 403: the key lacks the scope, or (passport / driving licence) is not IP-allowlisted.
  # The server message is passed through verbatim.
  class PermissionDeniedError < Error; end

  # HTTP 404.
  class NotFoundError < Error; end

  # HTTP 409, e.g. an Idempotency-Key reused with a different body.
  class ConflictError < Error; end

  # HTTP 429.
  class RateLimitError < Error
    # @return [Float, nil] seconds from the Retry-After header; nil when the API sent none
    attr_reader :retry_after

    # @param message [String, nil]
    # @param retry_after [Numeric, nil]
    # @param options [Hash] see {Error#initialize}
    def initialize(message = nil, retry_after: nil, **options)
      super(message, **options)
      @retry_after = retry_after&.to_f
    end
  end

  # HTTP 5xx from the API or its upstreams.
  class UpstreamError < Error; end

  # The request failed before a usable response arrived (DNS, refused, reset, TLS...).
  class ConnectionError < Error
    # @return [Boolean] false for failures a retry cannot fix (e.g. TLS certificate errors)
    def retryable?
      @retryable != false
    end

    # @param message [String, nil]
    # @param retryable [Boolean]
    # @param options [Hash] see {Error#initialize}
    def initialize(message = nil, retryable: true, **options)
      super(message, **options)
      @retryable = retryable
    end
  end

  # A connect, read or write timeout. A kind of {ConnectionError}.
  class TimeoutError < ConnectionError; end

  # Webhook verification failed (bad signature, stale timestamp, missing secret/headers, bad payload).
  # The +code+ names the reason, e.g. "SIGNATURE_MISMATCH".
  class SignatureVerificationError < Error; end
end
