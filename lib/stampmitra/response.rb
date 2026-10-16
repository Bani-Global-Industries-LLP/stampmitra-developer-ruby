# frozen_string_literal: true

module StampMitra
  # HTTP metadata of a completed API call: status, headers, request id, the raw
  # body and how many attempts it took.
  class Response
    # @return [Integer] HTTP status of the final attempt
    attr_reader :status
    # @return [Hash{String => String}] response headers, lower-case names
    attr_reader :headers
    # @return [String] the raw response body
    attr_reader :body
    # @return [Integer] number of HTTP attempts made (1 when nothing was retried)
    attr_reader :attempts
    # @return [String, nil] the value of the X-Request-Id header, when the API sent one
    attr_reader :request_id

    # @param status [Integer]
    # @param headers [Hash{String => String}]
    # @param body [String]
    # @param attempts [Integer]
    def initialize(status:, headers:, body:, attempts: 1)
      @status = status
      @headers = headers.freeze
      @body = body
      @attempts = attempts
      @request_id = headers['x-request-id']
    end

    # @return [Boolean] true for any 2xx status
    def success?
      status >= 200 && status < 300
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} status=#{status} attempts=#{attempts} request_id=#{request_id.inspect}>"
    end
  end

  # What +client.with_response.<resource>.<method>+ returns: the typed result
  # together with the {Response}. It destructures: +data, response = result+.
  class Result
    # @return [Object] the typed model (or Array of models)
    attr_reader :data
    # @return [Response]
    attr_reader :response

    # @param data [Object]
    # @param response [Response]
    def initialize(data, response)
      @data = data
      @response = response
    end

    # @return [Integer] HTTP status
    def status
      response.status
    end

    # @return [Hash{String => String}] response headers
    def headers
      response.headers
    end

    # @return [String, nil] the X-Request-Id header, when present
    def request_id
      response.request_id
    end

    # Enables +data, response = client.with_response.orders.get('ord_1')+.
    # @return [Array(Object, Response)]
    def to_ary
      [data, response]
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} data=#{data.inspect} response=#{response.inspect}>"
    end
  end
end
