# frozen_string_literal: true

module StampMitra
  # Per-request options accepted by every resource method as +options: {...}+.
  #
  # * +timeout+ (Numeric, seconds, per attempt) overrides the client default
  # * +max_retries+ (Integer) overrides the client default; 0 disables retries
  # * +idempotency_key+ (String) replaces the auto-generated Idempotency-Key
  # * +headers+ (Hash) extra headers for this request
  # @api private
  class RequestOptions
    KNOWN = %i[timeout max_retries idempotency_key headers].freeze

    # @return [Numeric, nil]
    attr_reader :timeout
    # @return [Integer, nil]
    attr_reader :max_retries
    # @return [String, nil]
    attr_reader :idempotency_key
    # @return [Hash{String => String}]
    attr_reader :headers

    # Normalises a Hash (or an existing RequestOptions).
    #
    # @param value [Hash, RequestOptions, nil]
    # @return [RequestOptions]
    # @raise [ValidationError] for unknown or malformed options
    def self.build(value)
      return value if value.is_a?(RequestOptions)
      return new({}) if value.nil?
      raise ValidationError.for_field('options', 'options must be a Hash') unless value.is_a?(Hash)

      new(value)
    end

    # @param hash [Hash]
    def initialize(hash)
      opts = hash.transform_keys(&:to_sym)
      unknown = opts.keys - KNOWN
      raise ValidationError.for_field('options', "unknown request option(s): #{unknown.join(', ')}") unless unknown.empty?

      @timeout = positive_number(opts[:timeout], 'timeout')
      @max_retries = non_negative_int(opts[:max_retries], 'max_retries')
      @idempotency_key = key(opts[:idempotency_key])
      @headers = headers_hash(opts[:headers])
    end

    private

    def positive_number(value, name)
      return nil if value.nil?
      raise ValidationError.for_field(name, "#{name} must be a positive number of seconds") unless value.is_a?(Numeric) && value.positive?

      value.to_f
    end

    def non_negative_int(value, name)
      return nil if value.nil?
      raise ValidationError.for_field(name, "#{name} must be a non-negative Integer") unless value.is_a?(Integer) && value >= 0

      value
    end

    def key(value)
      return nil if value.nil?
      unless value.is_a?(String) && !value.strip.empty?
        raise ValidationError.for_field('idempotency_key',
                                        'idempotency_key must be a non-empty String')
      end

      Headers.check_value!('Idempotency-Key', value)
      value
    end

    def headers_hash(value)
      return {} if value.nil?
      raise ValidationError.for_field('headers', 'headers must be a Hash') unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, val), out|
        Headers.check_name!(name.to_s)
        Headers.check_value!(name.to_s, val.to_s)
        out[name.to_s] = val.to_s
      end
    end
  end

  # Header hygiene shared by request options, default headers and the transport.
  # @api private
  module Headers
    TOKEN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/

    module_function

    # @param name [String]
    # @raise [ValidationError] when +name+ is not a valid HTTP header name
    def check_name!(name)
      raise ValidationError.for_field('headers', "invalid header name #{name.inspect}") unless TOKEN.match?(name)
    end

    # @param name [String]
    # @param value [String]
    # @raise [ValidationError] when +value+ could split the request (CR, LF or NUL)
    def check_value!(name, value)
      raise ValidationError.for_field('headers', "header #{name} must not contain CR, LF or NUL") if value.match?(/[\r\n\0]/)
    end
  end
end
