# frozen_string_literal: true

require 'uri'

module StampMitra
  # Methods shared by {Client} and the view returned by {Client#with_response}.
  module ResourceReaders
    # @return [Resources::Verify] identity verification
    attr_reader :verify
    # @return [Resources::Services] service catalogue
    attr_reader :services
    # @return [Resources::Estamp] e-Stamp reference data and helpers
    attr_reader :estamp
    # @return [Resources::Orders] orders
    attr_reader :orders
    # @return [Resources::Payments] payments (+payments.intents+)
    attr_reader :payments
    # @return [Resources::Usage] usage metering
    attr_reader :usage
    # @return [Resources::Logs] API call logs
    attr_reader :logs
    # @return [Resources::Webhooks] webhooks (+webhooks.events+)
    attr_reader :webhooks

    private

    def build_resources(transport, validate_input:, with_response:)
      opts = { validate_input: validate_input, with_response: with_response }
      @verify = Resources::Verify.new(transport, **opts)
      @services = Resources::Services.new(transport, **opts)
      @estamp = Resources::Estamp.new(transport, **opts)
      @orders = Resources::Orders.new(transport, **opts)
      @payments = Resources::Payments.new(transport, **opts)
      @usage = Resources::Usage.new(transport, **opts)
      @logs = Resources::Logs.new(transport, **opts)
      @webhooks = Resources::Webhooks.new(transport, **opts)
    end
  end

  # The StampMitra Developer API client.
  #
  #   client = StampMitra::Client.new(api_key: ENV['STAMPMITRA_API_KEY'])
  #   result = client.verify.pan(pan: 'ABCDE1234F')
  #
  # Server-side only: never ship +sk_+ keys in mobile apps, browsers or public repositories.
  #
  # Every resource method accepts a trailing +options:+ Hash with +timeout:+ (seconds, per attempt),
  # +max_retries:+, +idempotency_key:+ and +headers:+ for that call only.
  class Client
    include ResourceReaders

    # Production API base URL.
    DEFAULT_BASE_URL = 'https://api-b2b.stampmitra.in'
    # Accepted API key format.
    KEY_PATTERN = /\Ask_(test|live)_[A-Za-z0-9_-]{8,}\z/
    # Hosts for which plain http:// is accepted (mock servers, local development).
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    # @return [String] "test", "live", or "custom" (non +sk_+ key accepted through +allow_custom_key+)
    attr_reader :environment
    # @return [String] the API base URL
    attr_reader :base_url

    # @param api_key [String, nil] defaults to the +STAMPMITRA_API_KEY+ environment variable
    # @param base_url [String] must be https (http only for localhost / 127.0.0.1 / ::1) and carry no credentials
    # @param timeout [Numeric] seconds, per attempt (connect, each read and each write); default 30
    # @param max_retries [Integer] automatic retries for retry-safe requests; default 2
    # @param adapter [#call, nil] custom HTTP adapter, see {NetHttpAdapter}
    # @param default_headers [Hash{String => String}] sent with every request
    # @param app_info [Hash, nil] +{ name:, version:, url: }+ appended to the User-Agent
    # @param logger [Logger, nil] receives redacted debug logs; nothing is logged without it
    # @param validate_input [Boolean] run client-side validators before sending (default true)
    # @param allow_custom_key [Boolean] accept keys that are not +sk_test_...+ / +sk_live_...+
    # @param sleeper [#call, nil] receives the backoff delay in seconds (for tests); defaults to +Kernel.sleep+
    # @raise [AuthenticationError] when no key is given or its format is wrong
    # @raise [ValidationError] for an insecure or malformed +base_url+ or invalid option values
    def initialize(api_key: nil, base_url: DEFAULT_BASE_URL, timeout: 30, max_retries: 2, adapter: nil, default_headers: {},
                   app_info: nil, logger: nil, validate_input: true, allow_custom_key: false, sleeper: nil)
      @base_url = normalise_base_url(base_url)
      key = resolve_key(api_key)
      @environment = detect_environment(key, allow_custom_key)
      transport = Transport.new(
        api_key: Secret.new(key), base_url: @base_url, timeout: positive(timeout, 'timeout'),
        max_retries: non_negative(max_retries, 'max_retries'), adapter: adapter || NetHttpAdapter.new,
        default_headers: sanitise_headers(default_headers), user_agent: user_agent(app_info), logger: logger, sleeper: sleeper
      )
      @transport = transport
      @validate_input = validate_input
      build_resources(transport, validate_input: validate_input, with_response: false)
    end

    # A view of this client whose resource methods return a {Result}: the typed data plus the {Response}
    # (status, headers, request id, raw body, attempts).
    #
    #   data, response = client.with_response.orders.get('ord_1')
    #   response.status # => 200
    #
    # @return [ResponseView]
    def with_response
      ResponseView.new(@transport, validate_input: @validate_input)
    end

    # Never includes the API key.
    # @return [String]
    def inspect
      "#<#{self.class.name} environment=#{environment.inspect} base_url=#{base_url.inspect}>"
    end
    alias to_s inspect

    # Clients are not serialisable (they hold a credential).
    # @raise [TypeError]
    def marshal_dump
      raise TypeError, 'StampMitra::Client cannot be serialised'
    end

    # {Client}-like object returned by {Client#with_response}.
    class ResponseView
      include ResourceReaders

      # @param transport [Transport]
      # @param validate_input [Boolean]
      def initialize(transport, validate_input:)
        build_resources(transport, validate_input: validate_input, with_response: true)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end
      alias to_s inspect
    end

    private

    def resolve_key(api_key)
      key = (api_key || ENV.fetch('STAMPMITRA_API_KEY', nil)).to_s.strip
      raise AuthenticationError.new('No API key provided. Pass api_key: or set STAMPMITRA_API_KEY.', code: 'MISSING_API_KEY') if key.empty?

      key
    end

    def detect_environment(key, allow_custom_key)
      match = KEY_PATTERN.match(key)
      return match[1] if match
      unless allow_custom_key
        raise AuthenticationError.new('API key must look like sk_test_... or sk_live_... (pass allow_custom_key: true to override).',
                                      code: 'INVALID_API_KEY_FORMAT')
      end
      Headers.check_value!('Authorization', key)
      'custom'
    end

    # The API key travels in the Authorization header, so plain http is only allowed for loopback hosts.
    def normalise_base_url(value)
      uri = parse_uri(value)
      host = uri.hostname.to_s.downcase
      unless !host.empty? && %w[http https].include?(uri.scheme)
        raise ValidationError.for_field('base_url', 'base_url must be an absolute http(s) URL with a host')
      end
      raise ValidationError.for_field('base_url', 'base_url must not contain credentials') if uri.userinfo
      raise ValidationError.for_field('base_url', 'base_url must not contain a query string or fragment') if uri.query || uri.fragment
      if uri.scheme == 'http' && !LOOPBACK_HOSTS.include?(host)
        raise ValidationError.for_field('base_url', 'base_url must use https (http is only allowed for localhost)')
      end

      uri.to_s.chomp('/')
    end

    def parse_uri(value)
      raise ValidationError.for_field('base_url', 'base_url must be a String') unless value.is_a?(String)

      URI.parse(value.strip)
    rescue URI::InvalidURIError
      raise ValidationError.for_field('base_url', 'base_url is not a valid URL')
    end

    def positive(value, name)
      raise ValidationError.for_field(name, "#{name} must be a positive number of seconds") unless value.is_a?(Numeric) && value.positive?

      value.to_f
    end

    def non_negative(value, name)
      raise ValidationError.for_field(name, "#{name} must be a non-negative Integer") unless value.is_a?(Integer) && value >= 0

      value
    end

    def sanitise_headers(headers)
      raise ValidationError.for_field('default_headers', 'default_headers must be a Hash') unless headers.is_a?(Hash)

      headers.each_with_object({}) do |(name, value), out|
        Headers.check_name!(name.to_s)
        Headers.check_value!(name.to_s, value.to_s)
        if Transport::FORBIDDEN_HEADERS.include?(name.to_s.downcase)
          raise ValidationError.for_field('default_headers', "header #{name} is managed by the client and cannot be overridden")
        end

        out[name.to_s] = value.to_s
      end
    end

    def user_agent(app_info)
      agent = "stampmitra-ruby/#{VERSION} (Ruby #{RUBY_VERSION})"
      return agent unless app_info.is_a?(Hash) && app_info[:name]

      extra = app_info[:name].to_s
      extra += "/#{app_info[:version]}" if app_info[:version]
      extra += " (#{app_info[:url]})" if app_info[:url]
      "#{agent} #{extra.gsub(/[[:cntrl:]]/, '')}"
    end
  end
end
