# frozen_string_literal: true

require 'json'
require 'openssl'

module StampMitra
  # Verifies and parses webhook deliveries.
  #
  # Scheme: +signature = hex(HMAC-SHA256(secret, "#{timestamp}.#{raw_body}"))+, where +raw_body+ is the
  # request body exactly as received (do NOT parse and re-encode it) and +timestamp+ is Unix seconds.
  # Deliveries carry the headers +X-Webhook-Signature+, +X-Webhook-Timestamp+ and +X-Webhook-Event-Id+.
  # The comparison is constant-time and timestamps further than +tolerance+ (default 300s) from now are rejected.
  #
  #   event = StampMitra::Webhook.construct_event_from_headers(payload: request.body.read, headers: request.env, secret: ENV['WHSEC'])
  #   case event
  #   when StampMitra::Webhook::OrderDocumentReady then fetch_documents(event.core_order_id)
  #   end
  module Webhook
    # Header carrying the hex HMAC-SHA256 signature.
    HEADER_SIGNATURE = 'X-Webhook-Signature'
    # Header carrying the Unix timestamp (seconds) that is part of the signed message.
    HEADER_TIMESTAMP = 'X-Webhook-Timestamp'
    # Header carrying the unique delivery id.
    HEADER_EVENT_ID = 'X-Webhook-Event-Id'
    # Default timestamp tolerance in seconds.
    DEFAULT_TOLERANCE = 300

    # Webhook event names documented for the order lifecycle.
    EVENT_TYPES = %w[
      order.created order.payment_confirmed order.fulfilment_started order.fulfilment_completed
      order.failed order.cancelled order.refund_completed order.document_ready
    ].freeze

    # Failure reason: the timestamp header is not Unix seconds (see {Webhook.failure_reason}).
    REASON_INVALID_TIMESTAMP = 'invalid_timestamp'
    # Failure reason: the timestamp is further than the tolerance from now.
    REASON_OUTSIDE_TOLERANCE = 'timestamp_outside_tolerance'
    # Failure reason: the signature does not match the payload, timestamp and secret.
    REASON_MISMATCH = 'signature_mismatch'

    # A delivered event. Known fields are readers; any extra fields the server adds stay available through
    # {Model#[]} and {Model#to_h}. Subclasses exist for the eight +order.*+ event types.
    class Event < Model
      # The +order.*+ type name of this class, or nil for an unrecognised event.
      TYPE = nil

      # @!attribute [r] core_order_id
      #   @return [String, nil] internal order id the event is about
      attribute :core_order_id
      # @!attribute [r] core_event_type
      #   @return [String, nil] upstream event type, e.g. "ORDER_CREATED"
      attribute :core_event_type
      # @!attribute [r] occurred_at
      #   @return [String, nil] ISO 8601 time the event happened
      attribute :occurred_at

      # @return [String, nil] the X-Webhook-Event-Id delivery header, when it was supplied
      attr_reader :event_id

      # @param data [Hash, nil] decoded payload
      # @param event_id [String, nil] value of the X-Webhook-Event-Id header
      # @param response [Response, nil]
      # @param fields [Hash] payload fields when +data+ is omitted
      def initialize(data = nil, event_id: nil, response: nil, **fields)
        super(data, response: response, **fields)
        @event_id = event_id
      end

      # @return [String, nil] the +order.*+ event name (e.g. "order.created"); nil for unrecognised events
      def type
        self.class::TYPE
      end
    end

    # +order.created+
    class OrderCreated < Event
      # @return [String]
      TYPE = 'order.created'
    end

    # +order.payment_confirmed+
    class OrderPaymentConfirmed < Event
      # @return [String]
      TYPE = 'order.payment_confirmed'
    end

    # +order.fulfilment_started+
    class OrderFulfilmentStarted < Event
      # @return [String]
      TYPE = 'order.fulfilment_started'
    end

    # +order.fulfilment_completed+
    class OrderFulfilmentCompleted < Event
      # @return [String]
      TYPE = 'order.fulfilment_completed'
    end

    # +order.failed+
    class OrderFailed < Event
      # @return [String]
      TYPE = 'order.failed'
    end

    # +order.cancelled+
    class OrderCancelled < Event
      # @return [String]
      TYPE = 'order.cancelled'
    end

    # +order.refund_completed+
    class OrderRefundCompleted < Event
      # @return [String]
      TYPE = 'order.refund_completed'
    end

    # +order.document_ready+
    class OrderDocumentReady < Event
      # @return [String]
      TYPE = 'order.document_ready'
    end

    # Maps the payload's +coreEventType+ to its typed event class.
    EVENT_CLASSES = {
      'ORDER_CREATED' => OrderCreated,
      'PAYMENT_CONFIRMED' => OrderPaymentConfirmed,
      'FULFILMENT_STARTED' => OrderFulfilmentStarted,
      'FULFILMENT_COMPLETED' => OrderFulfilmentCompleted,
      'ORDER_FAILED' => OrderFailed,
      'ORDER_CANCELLED' => OrderCancelled,
      'REFUND_COMPLETED' => OrderRefundCompleted,
      'DOCUMENT_READY' => OrderDocumentReady
    }.freeze

    module_function

    # Computes the expected signature (useful for tests and local replays).
    #
    # @param payload [String] raw request body
    # @param timestamp [String, Integer] Unix seconds
    # @param secret [String] endpoint signing secret
    # @return [String] lower-case hex HMAC-SHA256
    def sign(payload:, timestamp:, secret:)
      check_secret!(secret)
      check_payload!(payload)
      OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.".b + payload.b)
    end

    # Why verification fails, or nil when the delivery is authentic and fresh.
    #
    # @param payload [String] raw request body, exactly as received
    # @param timestamp [String, Integer] value of X-Webhook-Timestamp
    # @param signature [String] value of X-Webhook-Signature
    # @param secret [String] endpoint signing secret
    # @param tolerance [Integer] accepted clock skew in seconds (default 300)
    # @param now [Integer, Time, nil] current time override for tests
    # @return [String, nil] {REASON_INVALID_TIMESTAMP}, {REASON_OUTSIDE_TOLERANCE}, {REASON_MISMATCH} or nil
    # @raise [SignatureVerificationError] for an empty secret or a payload that is not a String
    def failure_reason(payload:, timestamp:, signature:, secret:, tolerance: DEFAULT_TOLERANCE, now: nil)
      check_secret!(secret)
      check_payload!(payload)
      ts = timestamp.to_s
      return REASON_INVALID_TIMESTAMP unless /\A[0-9]{1,15}\z/.match?(ts)
      return REASON_OUTSIDE_TOLERANCE if (current_time(now) - ts.to_i).abs > tolerance

      expected = sign(payload: payload, timestamp: ts, secret: secret)
      secure_compare(expected, signature.to_s) ? nil : REASON_MISMATCH
    end

    # @return [Boolean] true when the signature matches and the timestamp is within tolerance
    # @see failure_reason
    def verify_signature(payload:, timestamp:, signature:, secret:, tolerance: DEFAULT_TOLERANCE, now: nil) # rubocop:disable Naming/PredicateMethod
      failure_reason(payload: payload, timestamp: timestamp, signature: signature, secret: secret, tolerance: tolerance, now: now).nil?
    end

    # Verifies the delivery, then parses it into a typed {Event}.
    #
    # @param payload [String] raw request body
    # @param timestamp [String, Integer]
    # @param signature [String]
    # @param secret [String]
    # @param tolerance [Integer]
    # @param event_id [String, nil] X-Webhook-Event-Id header value
    # @param now [Integer, Time, nil]
    # @return [Event] an instance of one of the +Order*+ subclasses, or {Event} for an unrecognised type
    # @raise [SignatureVerificationError] when verification fails or the payload is not a JSON object
    def construct_event(payload:, timestamp:, signature:, secret:, tolerance: DEFAULT_TOLERANCE, event_id: nil, now: nil)
      reason = failure_reason(payload: payload, timestamp: timestamp, signature: signature, secret: secret, tolerance: tolerance, now: now)
      raise SignatureVerificationError.new("Webhook verification failed: #{reason}", code: reason.upcase) if reason

      parse_event(payload, event_id)
    end

    # {construct_event} reading the three delivery headers from +headers+: a Hash with any header casing, a Rack
    # +env+ (+HTTP_X_WEBHOOK_SIGNATURE+), or any object answering +[]+ such as Rails' +request.headers+.
    #
    # @param payload [String] raw request body
    # @param headers [Hash, #[]] request headers
    # @param secret [String]
    # @param tolerance [Integer]
    # @param now [Integer, Time, nil]
    # @return [Event]
    # @raise [SignatureVerificationError] when a header is missing, verification fails or the payload is malformed
    def construct_event_from_headers(payload:, headers:, secret:, tolerance: DEFAULT_TOLERANCE, now: nil)
      signature = header(headers, HEADER_SIGNATURE)
      timestamp = header(headers, HEADER_TIMESTAMP)
      if signature.nil? || timestamp.nil?
        raise SignatureVerificationError.new("Missing #{HEADER_SIGNATURE} or #{HEADER_TIMESTAMP} header", code: 'MISSING_HEADERS')
      end

      construct_event(payload: payload, timestamp: timestamp, signature: signature, secret: secret, tolerance: tolerance,
                      event_id: header(headers, HEADER_EVENT_ID), now: now)
    end

    # Constant-time string comparison that does not leak where two strings differ. Strings of different length are
    # unequal (the expected signature length is public). Uses +OpenSSL.fixed_length_secure_compare+ when the
    # openssl library provides it, otherwise an equivalent XOR loop.
    #
    # @param left [String]
    # @param right [String]
    # @return [Boolean]
    def secure_compare(left, right)
      left = left.to_s.b
      right = right.to_s.b
      return false unless left.bytesize == right.bytesize
      return OpenSSL.fixed_length_secure_compare(left, right) if OpenSSL.respond_to?(:fixed_length_secure_compare)

      xor_equal?(left, right)
    end

    # @api private
    def xor_equal?(left, right)
      diff = 0
      right.each_byte.with_index { |byte, i| diff |= byte ^ left.getbyte(i) }
      diff.zero?
    end

    # @api private
    def parse_event(payload, event_id)
      data = JSON.parse(payload)
      raise SignatureVerificationError.new('Webhook payload is not a JSON object', code: 'INVALID_PAYLOAD') unless data.is_a?(Hash)

      (EVENT_CLASSES[data['coreEventType']] || Event).new(data, event_id: event_id)
    rescue JSON::ParserError
      raise SignatureVerificationError.new('Webhook payload is not valid JSON', code: 'INVALID_PAYLOAD')
    end

    # @api private
    def header(headers, name)
      env_name = "HTTP_#{name.upcase.tr('-', '_')}"
      value = lookup(headers, name) || lookup(headers, name.downcase) || lookup(headers, env_name)
      if value.nil? && headers.respond_to?(:each_pair)
        match = headers.each_pair.find { |key, _| key.to_s.casecmp?(name) || key.to_s == env_name }
        value = match&.last
      end
      value = value.first if value.is_a?(Array)
      value&.to_s
    end

    # @api private
    def lookup(headers, key)
      headers[key]
    rescue StandardError
      nil
    end

    # @api private
    def current_time(now)
      case now
      when nil then Time.now.to_i
      when Time then now.to_i
      else Integer(now)
      end
    end

    # @api private
    def check_secret!(secret)
      return if secret.is_a?(String) && !secret.empty?

      raise SignatureVerificationError.new('Webhook secret must not be empty', code: 'MISSING_SECRET')
    end

    # @api private
    def check_payload!(payload)
      return if payload.is_a?(String)

      raise SignatureVerificationError.new('payload must be the raw request body as a String (do not pass parsed JSON)', code: 'INVALID_PAYLOAD')
    end
  end
end
