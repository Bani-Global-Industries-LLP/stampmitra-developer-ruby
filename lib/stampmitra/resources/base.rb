# frozen_string_literal: true

module StampMitra
  # Resource classes grouping API operations.
  module Resources
    # Shared plumbing of every resource. Not part of the public API.
    # @api private
    class Base
      # @param transport [Transport]
      # @param validate_input [Boolean] run client-side validators before sending
      # @param with_response [Boolean] return :Result (typed data + :Response) instead of the bare data
      def initialize(transport, validate_input: true, with_response: false)
        @transport = transport
        @validate_input = validate_input
        @with_response = with_response
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end
      alias to_s inspect

      private

      attr_reader :transport

      def validate?
        @validate_input
      end

      def api_get(path, model, query: nil, options: nil)
        run(:get, path, model, query: query, options: options)
      end

      # Idempotent by default: the transport adds an Idempotency-Key and reuses it across retries.
      # +retry_policy+: :never (never auto-retried), :safe (retried without a key), nil (retried only with a key).
      def api_post(path, model, body = nil, options: nil, idempotent: true, retry_policy: nil, multipart: nil)
        run(:post, path, model, body: body && compact(body), options: options, idempotent: idempotent, retry_policy: retry_policy,
                                multipart: multipart)
      end

      def run(method, path, model, query: nil, body: nil, options: nil, idempotent: false, retry_policy: nil, multipart: nil)
        data, response = transport.request(method, path, query: query, body: body, options: options, idempotent: idempotent,
                                                         retry_policy: retry_policy, multipart: multipart)
        typed = model.is_a?(Class) ? build(model, data, response) : data
        @with_response ? Result.new(typed, response) : typed
      end

      def build(model, data, response)
        model.new(data, response: response)
      rescue ArgumentError
        raise Error.new("Unexpected response shape for #{model.name.to_s.split('::').last}: expected #{model.name} fields, got #{data.class}",
                        status: response.status, code: 'INVALID_RESPONSE', request_id: response.request_id, body: response.body,
                        headers: response.headers)
      end

      # Percent-encodes one path segment and rejects values that could change the route.
      def seg(value, name)
        text = value.is_a?(Symbol) || value.is_a?(Integer) ? value.to_s : value
        raise ValidationError.for_field(name, "#{name} must be a String") unless text.is_a?(String)
        raise ValidationError.for_field(name, "#{name} must not be empty") if text.strip.empty?
        raise ValidationError.for_field(name, "#{name} must not be a dot segment") if ['.', '..'].include?(text)
        raise ValidationError.for_field(name, "#{name} must not contain slashes") if text.match?(%r{[/\\]})
        raise ValidationError.for_field(name, "#{name} must be valid UTF-8") unless text.valid_encoding?

        text.b.gsub(/[^A-Za-z0-9\-._~]/n) { |char| format('%%%02X', char.ord) }
      end

      # Follows +next_cursor+ page by page: +fetch.call(cursor)+ returns a page (or a Result wrapping one); each page is yielded.
      def walk_pages(first_cursor, fetch)
        cursor = first_cursor
        loop do
          page = fetch.call(cursor)
          page = page.data if page.is_a?(Result)
          yield page
          following = page.next_cursor
          break if following.nil? || following.to_s.empty?
          raise Error.new('The API returned the same pagination cursor twice', code: 'PAGINATION_LOOP') if following == cursor

          cursor = following
        end
        nil
      end

      # Shared body of the lazy +each+ / +each_page+ iterators built around +list_method+.
      def each_item(each_name, pages_name, list_method, filters, &block)
        return enum_for(each_name, **filters) unless block

        each_page_of(pages_name, list_method, filters) { |page| Array(page.items).each(&block) }
        nil
      end

      def each_page_of(pages_name, list_method, filters, &block)
        return enum_for(pages_name, **filters) unless block

        params = filters.except(:cursor)
        walk_pages(filters[:cursor], ->(cursor) { public_send(list_method, **params, cursor: cursor) }, &block)
      end

      def compact(hash)
        hash.compact
      end

      def require_string!(value, name)
        return if value.is_a?(String) && !value.strip.empty?

        raise ValidationError.for_field(name, "#{name} is required")
      end
    end
  end
end
