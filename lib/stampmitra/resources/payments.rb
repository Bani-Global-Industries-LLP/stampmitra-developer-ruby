# frozen_string_literal: true

module StampMitra
  module Resources
    # Payment resources (+client.payments+).
    class Payments
      # @return [PaymentIntents] +client.payments.intents+
      attr_reader :intents

      # @param transport [Transport]
      # @param options [Hash] +validate_input:+ and +with_response:+
      def initialize(transport, **options)
        @intents = PaymentIntents.new(transport, **options)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end
      alias to_s inspect
    end

    # Payment intents (+client.payments.intents+).
    class PaymentIntents < Base
      # Creates a payment intent (POST /v1/payments/intents). An Idempotency-Key is generated
      # automatically (and reused across retries); retrying with the same key returns the existing intent.
      #
      # @param external_order_id [String]
      # @param amount_minor [Integer] amount in minor units (paise)
      # @param currency [String] e.g. "INR"
      # @param payment_connection_id [String]
      # @param options [Hash, nil]
      # @return [Models::PaymentIntent]
      def create(external_order_id:, amount_minor:, currency:, payment_connection_id:, options: nil)
        if validate?
          require_string!(external_order_id, 'externalOrderId')
          require_string!(currency, 'currency')
          require_string!(payment_connection_id, 'paymentConnectionId')
          unless amount_minor.is_a?(Integer) && amount_minor.positive?
            raise ValidationError.for_field('amountMinor', 'amountMinor must be a positive Integer (minor units)')
          end
        end
        body = { 'externalOrderId' => external_order_id, 'amountMinor' => amount_minor, 'currency' => currency,
                 'paymentConnectionId' => payment_connection_id }
        api_post('/v1/payments/intents', Models::PaymentIntent, body, options: options)
      end

      # Fetches a payment intent (GET /v1/payments/intents/:id).
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::PaymentIntent]
      def get(id, options: nil)
        api_get("/v1/payments/intents/#{seg(id, :id)}", Models::PaymentIntent, options: options)
      end
    end
  end
end
