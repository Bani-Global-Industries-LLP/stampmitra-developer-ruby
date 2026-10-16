# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'
require 'uri'

module StampMitra
  # Builds requests, sends them through the HTTP adapter, retries safely and maps
  # failures to typed errors.
  #
  # Retry rules:
  # * GET is always retry-safe.
  # * POST is retried only when it carries an Idempotency-Key. The gem generates a
  #   CSPRNG UUIDv4 key for every POST the API accepts one on (verification, duty,
  #   parties, orders, payment intents) and reuses the same key on every attempt, so
  #   a retry replays the original result instead of billing twice. Webhook replay
  #   is never retried unless the caller supplies a key.
  # * Retried: 429, 502, 503, 504, connection errors and timeouts.
  # * Backoff: exponential with full jitter (0.5s base, 8s cap); Retry-After
  #   (seconds or HTTP date, capped at 60s) wins when the server sends it.
  # @api private
  class Transport
    RETRY_STATUSES = [429, 502, 503, 504].freeze
    BACKOFF_BASE = 0.5
    BACKOFF_CAP = 8.0
    RETRY_AFTER_CAP = 60.0
    FORBIDDEN_HEADERS = %w[authorization x-api-key host content-length transfer-encoding connection].freeze

    # @return [Integer] default number of automatic retries
    attr_reader :max_retries

    # @param api_key [Secret]
    # @param base_url [String] validated, without trailing slash
    # @param timeout [Float]
    # @param max_retries [Integer]
    # @param adapter [#call]
    # @param default_headers [Hash{String => String}]
    # @param user_agent [String]
    # @param logger [Logger, nil]
    # @param sleeper [#call]
    def initialize(api_key:, base_url:, timeout:, max_retries:, adapter:, default_headers:, user_agent:, logger: nil, sleeper: nil)
      @api_key = api_key
      @base_url = base_url
      @timeout = timeout
      @max_retries = max_retries
      @adapter = adapter
      @default_headers = default_headers
      @user_agent = user_agent
      @logger = logger
      @sleeper = sleeper || ->(seconds) { Kernel.sleep(seconds) if seconds.positive? }
    end

    # Keeps the API key out of +inspect+ / +pp+ output.
    # @return [String]
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end
    alias to_s inspect

    # Performs a request with retries.
    #
    # @param method [Symbol] +:get+ or +:post+
    # @param path [String] path starting with +/v1/+, already encoded
    # @param query [Hash, nil]
    # @param body [Hash, nil] JSON body for POST
    # @param options [Hash, RequestOptions, nil]
    # @param idempotent [Boolean] generate an Idempotency-Key when the caller gave none
    # @return [Array(Object, Response)] decoded JSON and response metadata
    # @raise [Error]
    def request(method, path, query: nil, body: nil, options: nil, idempotent: false)
      execute(prepare(method, path, RequestOptions.build(options), query: query, body: body, idempotent: idempotent))
    end

    private

    # Everything that stays constant across the attempts of one logical request.
    Call = Struct.new(:verb, :url, :headers, :payload, :timeout, :retry_safe, :max_retries)
    private_constant :Call

    def prepare(method, path, opts, query:, body:, idempotent:)
      key = opts.idempotency_key || (idempotent && method == :post ? generate_key : nil)
      Call.new(method, build_url(path, query), build_headers(opts, key), (JSON.generate(body.nil? || body.empty? ? {} : body) if method == :post),
               opts.timeout || @timeout, method == :get || !key.nil?, opts.max_retries || @max_retries)
    end

    def execute(call)
      attempt = 0
      loop do
        attempt += 1
        outcome = attempt_once(call, attempt)
        return finish(outcome, attempt) if success?(outcome[:status])

        error = outcome[:error]
        raise error unless call.retry_safe && attempt <= call.max_retries && retryable?(error)

        pause(delay_for(error, attempt))
      end
    end

    def success?(status)
      !status.nil? && status >= 200 && status < 300
    end

    # One HTTP attempt: returns { status:, headers:, body: } or { error: }.
    def attempt_once(call, attempt)
      log_request(call, attempt)
      raw = @adapter.call(method: call.verb, url: call.url, headers: call.headers, body: call.payload, timeout: call.timeout)
      log_response(raw[:status], raw[:body], attempt)
      return raw if success?(raw[:status])

      raw.merge(error: map_error(raw[:status], raw[:body], raw[:headers]))
    rescue ConnectionError => e
      debug { "stampmitra transport error attempt=#{attempt} error=#{e.class}" }
      { error: e }
    end

    def finish(raw, attempts)
      response = Response.new(status: raw[:status], headers: raw[:headers], body: raw[:body], attempts: attempts)
      [decode_success(raw), response]
    end

    def retryable?(error)
      case error
      when ConnectionError then error.retryable?
      else RETRY_STATUSES.include?(error.status)
      end
    end

    def delay_for(error, attempt)
      retry_after = error.is_a?(RateLimitError) ? error.retry_after : parse_retry_after(error.headers['retry-after'])
      retry_after ? [retry_after, RETRY_AFTER_CAP].min : backoff(attempt)
    end

    def backoff(attempt)
      ceiling = [BACKOFF_CAP, BACKOFF_BASE * (2**(attempt - 1))].min
      SecureRandom.random_number * ceiling # full jitter
    end

    def pause(seconds)
      @sleeper.call(seconds)
    end

    def generate_key
      SecureRandom.uuid
    rescue StandardError, NotImplementedError
      raise Error.new('No secure random source is available to generate an Idempotency-Key', code: 'NO_SECURE_RANDOM')
    end

    def build_url(path, query)
      url = "#{@base_url}#{path}"
      params = (query || {}).compact.map { |k, v| [k.to_s, query_value(v)] }
      params.empty? ? url : "#{url}?#{URI.encode_www_form(params)}"
    end

    def query_value(value)
      case value
      when Time then value.utc.iso8601(3)
      when true then 'true'
      when false then 'false'
      else value.to_s
      end
    end

    def build_headers(opts, key)
      merged = {}
      add = lambda do |name, value|
        merged[name.to_s.downcase] = [name.to_s, value.to_s]
      end
      add.call('Authorization', "Bearer #{@api_key.reveal}")
      add.call('Accept', 'application/json')
      add.call('Content-Type', 'application/json')
      add.call('User-Agent', @user_agent)
      @default_headers.each { |name, value| add.call(name, value) }
      opts.headers.each do |name, value|
        reject_forbidden!(name)
        add.call(name, value)
      end
      add.call('Idempotency-Key', key) if key
      merged.values.to_h
    end

    def reject_forbidden!(name)
      return unless FORBIDDEN_HEADERS.include?(name.downcase)

      raise ValidationError.for_field('headers', "header #{name} cannot be set per request (the client manages it)")
    end

    def decode_success(raw)
      text = raw[:body].to_s
      return {} if text.strip.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      raise Error.new('The API returned a success status with a non-JSON body',
                      status: raw[:status], code: 'INVALID_RESPONSE', request_id: raw[:headers]['x-request-id'],
                      body: text, headers: raw[:headers])
    end

    def map_error(status, text, headers)
      parsed = parse_json(text)
      err = parsed.is_a?(Hash) && parsed['error'].is_a?(Hash) ? parsed['error'] : {}
      message = string_or_nil(err['message'])
      message = Redaction.scrub_keys(message) if message
      details = {
        status: status, code: string_or_nil(err['code']), field: string_or_nil(err['field']), headers: headers,
        request_id: string_or_nil(err['requestId']) || headers['x-request-id'],
        body: if parsed.is_a?(Hash) || parsed.is_a?(Array)
                parsed
              else
                (text.to_s.empty? ? nil : text)
              end
      }
      error_class(status).then do |klass|
        if klass == RateLimitError
          klass.new(message, retry_after: parse_retry_after(headers['retry-after']), **details)
        else
          klass.new(message, **details)
        end
      end
    end

    def error_class(status)
      case status
      when 400 then ValidationError
      when 401 then AuthenticationError
      when 402 then PaymentRequiredError
      when 403 then PermissionDeniedError
      when 404 then NotFoundError
      when 409 then ConflictError
      when 429 then RateLimitError
      when 500..599 then UpstreamError
      else Error
      end
    end

    def parse_json(text)
      return nil if text.nil? || text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def string_or_nil(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end

    def parse_retry_after(value)
      return nil if value.nil?

      text = value.strip
      return [text.to_f, 0.0].max if text.match?(/\A\d+(?:\.\d+)?\z/)

      [Time.httpdate(text) - Time.now, 0.0].max
    rescue ArgumentError
      nil
    end

    def log_request(call, attempt)
      debug do
        "stampmitra request attempt=#{attempt} #{call.verb.to_s.upcase} #{call.url} " \
          "headers=#{JSON.generate(Redaction.headers(call.headers))} body=#{Redaction.body(call.payload)}"
      end
    end

    def log_response(status, text, attempt)
      debug { "stampmitra response attempt=#{attempt} status=#{status} body=#{Redaction.body(text)}" }
    end

    def debug(&block)
      @logger&.debug(&block)
    end
  end
end
