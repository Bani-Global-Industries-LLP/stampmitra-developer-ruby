# frozen_string_literal: true

module StampMitra
  module Resources
    # Usage metering (+client.usage+).
    class Usage < Base
      # Usage summary for the current billing period (GET /v1/usage/summary).
      #
      # @param options [Hash, nil]
      # @return [Models::UsageSummary]
      def summary(options: nil)
        api_get('/v1/usage/summary', Models::UsageSummary, options: options)
      end
    end
  end
end
