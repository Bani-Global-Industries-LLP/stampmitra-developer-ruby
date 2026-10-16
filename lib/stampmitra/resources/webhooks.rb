# frozen_string_literal: true

module StampMitra
  module Resources
    # Webhook resources (+client.webhooks+). To verify deliveries use {StampMitra::Webhook}.
    class Webhooks
      # @return [WebhookEvents] +client.webhooks.events+
      attr_reader :events

      # @param transport [Transport]
      # @param options [Hash] +validate_input:+ and +with_response:+
      def initialize(transport, **options)
        @events = WebhookEvents.new(transport, **options)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end
      alias to_s inspect
    end

    # Webhook delivery attempts (+client.webhooks.events+).
    class WebhookEvents < Base
      # Lists webhook delivery attempts (GET /v1/webhooks/events).
      #
      # @param limit [Integer, nil] page size
      # @param cursor [String, nil] opaque cursor from a previous response
      # @param options [Hash, nil]
      # @return [Models::GenericResponse] the upstream shape is not fixed by the API (+#items+, +#[]+, +#to_h+)
      def list(limit: nil, cursor: nil, options: nil)
        if validate? && !limit.nil? && !(limit.is_a?(Integer) && limit >= 1)
          raise ValidationError.for_field('limit', 'limit must be a positive Integer')
        end

        api_get('/v1/webhooks/events', Models::GenericResponse, query: { limit: limit, cursor: cursor }, options: options)
      end

      # Replays a delivery (POST /v1/webhooks/events/:id/replay). NOT idempotent: it is never retried
      # automatically unless you pass +options: { idempotency_key: }+.
      #
      # @param id [String] the webhook event id
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def replay(id, options: nil)
        api_post("/v1/webhooks/events/#{seg(id, :id)}/replay", Models::GenericResponse, nil, options: options, idempotent: false)
      end
    end
  end
end
