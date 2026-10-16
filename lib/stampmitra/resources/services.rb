# frozen_string_literal: true

module StampMitra
  module Resources
    # The service catalogue (+client.services+).
    class Services < Base
      # Lists the services your organization is entitled to (GET /v1/services).
      #
      # @param options [Hash, nil]
      # @return [Models::ServiceList] enumerable of {Models::Service}
      def list(options: nil)
        api_get('/v1/services', Models::ServiceList, options: options)
      end

      # Fetches one service (GET /v1/services/:serviceCode).
      #
      # @param service_code [String] e.g. "estamp.instrument.rent_agreement"
      # @param options [Hash, nil]
      # @return [Models::Service]
      def get(service_code, options: nil)
        api_get("/v1/services/#{seg(service_code, :service_code)}", Models::Service, options: options)
      end
    end
  end
end
