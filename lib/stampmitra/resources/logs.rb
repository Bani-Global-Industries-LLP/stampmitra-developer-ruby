# frozen_string_literal: true

module StampMitra
  module Resources
    # API call logs (+client.logs+).
    class Logs < Base
      # Accepted values of the +status+ filter.
      STATUSES = %w[success failure].freeze

      # One page of logs (GET /v1/logs).
      #
      # @param from [String, Time, nil] ISO 8601 lower bound (inclusive)
      # @param to [String, Time, nil] ISO 8601 upper bound (exclusive)
      # @param service [String, nil] one service code, e.g. "pan.verify"
      # @param status [String, Symbol, nil] "success" or "failure"
      # @param limit [Integer, nil] page size, 1-200 (server default 50)
      # @param cursor [String, nil] opaque cursor from a previous page
      # @param options [Hash, nil]
      # @return [Models::LogsPage] +#items+ and +#next_cursor+
      def list(from: nil, to: nil, service: nil, status: nil, limit: nil, cursor: nil, options: nil)
        status = status&.to_s
        if validate?
          raise ValidationError.for_field('status', "status must be 'success' or 'failure'") unless status.nil? || STATUSES.include?(status)
          unless limit.nil? || (limit.is_a?(Integer) && limit.between?(1, 200))
            raise ValidationError.for_field('limit', 'limit must be an Integer between 1 and 200')
          end
        end
        query = { from: from, to: to, service: service, status: status, limit: limit, cursor: cursor }
        api_get('/v1/logs', Models::LogsPage, query: query, options: options)
      end

      # Iterates every log entry, following +next_cursor+ lazily (one request per page, fetched on demand).
      # Without a block it returns an Enumerator, so +logs.each(limit: 100).lazy.select {...}.first(5)+ stops early.
      #
      # @param filters [Hash] the same filters as {#list} (+from+, +to+, +service+, +status+, +limit+, +cursor+, +options+)
      # @yieldparam entry [Models::LogEntry]
      # @return [Enumerator<Models::LogEntry>, nil] an Enumerator when no block is given
      def each(**filters, &block)
        return enum_for(:each, **filters) unless block

        each_page(**filters) { |page| Array(page.items).each(&block) }
        nil
      end

      # Iterates pages (+Models::LogsPage+) instead of entries.
      #
      # @param filters [Hash] see {#each}
      # @yieldparam page [Models::LogsPage]
      # @return [Enumerator<Models::LogsPage>, nil]
      def each_page(**filters)
        return enum_for(:each_page, **filters) unless block_given?

        cursor = filters[:cursor]
        params = filters.except(:cursor)
        loop do
          page = list(**params, cursor: cursor)
          page = page.data if page.is_a?(Result)
          yield page
          following = page.next_cursor
          break if following.nil? || following.to_s.empty?
          raise Error.new('The API returned the same pagination cursor twice', code: 'PAGINATION_LOOP') if following == cursor

          cursor = following
        end
        nil
      end
    end
  end
end
