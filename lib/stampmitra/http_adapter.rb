# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module StampMitra
  # The default HTTP adapter, built on Net::HTTP (standard library).
  #
  # * One fresh connection per request (+Connection: close+): a retried request can never be replayed
  #   silently on a stale keep-alive connection, which would double-send billed calls.
  # * Net::HTTP's own transparent retry is disabled (+max_retries = 0+); retries are the transport's job.
  # * Redirects are never followed, so credentials cannot be forwarded to another host.
  # * TLS certificates and host names are always verified (TLS 1.2 or newer).
  #
  # Any object responding to +call(method:, url:, headers:, body:, timeout:)+ and returning
  # +{ status:, headers:, body: }+ (or raising {ConnectionError} / {TimeoutError}) can replace it through
  # the +adapter:+ option of {Client#initialize}, e.g. to route traffic through a custom stack in tests.
  class NetHttpAdapter
    # Upper bound (seconds) for the connect phase, whatever the request timeout is.
    CONNECT_TIMEOUT_CAP = 10.0

    # Performs one HTTP request.
    #
    # @param method [Symbol] +:get+ or +:post+
    # @param url [String] absolute URL
    # @param headers [Hash{String => String}]
    # @param body [String, nil]
    # @param timeout [Numeric] seconds for connecting, and for each read and write
    # @return [Hash] +{ status: Integer, headers: Hash{String => String}, body: String }+
    # @raise [TimeoutError] on connect/read/write timeouts
    # @raise [ConnectionError] on any other transport failure
    def call(method:, url:, headers:, body:, timeout:)
      uri = URI.parse(url)
      http = build_http(uri, timeout)
      request = build_request(method, uri, headers, body)
      response = http.start { |connection| connection.request(request) }
      { status: response.code.to_i, headers: collect_headers(response), body: read_body(response) }
    rescue ::Net::OpenTimeout, ::Net::ReadTimeout, ::Net::WriteTimeout, Errno::ETIMEDOUT => e
      raise TimeoutError.new("Request timed out after #{timeout}s (#{e.class})")
    rescue OpenSSL::SSL::SSLError => e
      raise ConnectionError.new("TLS error: #{e.message}", retryable: false)
    rescue SocketError, SystemCallError, IOError, ::Net::HTTPBadResponse, ::Net::ProtocolError => e
      raise ConnectionError.new("Network error: #{e.class}: #{e.message}")
    end

    private

    def build_http(uri, timeout)
      http = ::Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == 'https'
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.min_version = OpenSSL::SSL::TLS1_2_VERSION
      end
      http.open_timeout = [timeout, CONNECT_TIMEOUT_CAP].min
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.max_retries = 0
      http
    end

    def build_request(method, uri, headers, body)
      klass = method == :post ? ::Net::HTTP::Post : ::Net::HTTP::Get
      request = klass.new(uri.request_uri)
      headers.each { |name, value| request[name] = value }
      request['Connection'] = 'close'
      request.body = body if body
      request
    end

    def collect_headers(response)
      response.each_header.to_h { |name, value| [name.downcase, value] }
    end

    def read_body(response)
      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
