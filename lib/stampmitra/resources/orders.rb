# frozen_string_literal: true

module StampMitra
  module Resources
    # Orders (+client.orders+). Orders are addressed by YOUR +external_order_id+.
    class Orders < Base
      # Creates an order (POST /v1/orders). An Idempotency-Key is generated
      # automatically (and reused across retries) unless you pass +options: { idempotency_key: }+.
      # The response carries +external_order_id+; use it with {#get}, {#get_status} and {#list_documents}.
      #
      # @param external_order_id [String] your order id
      # @param external_customer_id [String] your customer id
      # @param service_code [String] e.g. "estamp.instrument.rent_agreement"
      # @param details [Hash, nil] service specific order details
      # @param options [Hash, nil]
      # @return [Models::OrderReference]
      def create(external_order_id:, external_customer_id:, service_code:, details: nil, options: nil)
        if validate?
          require_string!(external_order_id, 'externalOrderId')
          require_string!(external_customer_id, 'externalCustomerId')
          require_string!(service_code, 'serviceCode')
        end
        body = { 'externalOrderId' => external_order_id, 'externalCustomerId' => external_customer_id,
                 'serviceCode' => service_code, 'details' => details }
        api_post('/v1/orders', Models::OrderReference, body, options: options)
      end

      # Fetches an order (GET /v1/orders/:id).
      #
      # @param id [String] the +external_order_id+
      # @param options [Hash, nil]
      # @return [Models::OrderDetail]
      def get(id, options: nil)
        api_get("/v1/orders/#{seg(id, :id)}", Models::OrderDetail, options: options)
      end

      # Order status (GET /v1/orders/:id/status).
      #
      # @param id [String] the +external_order_id+
      # @param options [Hash, nil]
      # @return [Models::OrderStatus]
      def get_status(id, options: nil)
        api_get("/v1/orders/#{seg(id, :id)}/status", Models::OrderStatus, options: options)
      end

      # Order payment (GET /v1/orders/:id/payment).
      #
      # @param id [String] the +external_order_id+
      # @param options [Hash, nil]
      # @return [Models::OrderPayment]
      def get_payment(id, options: nil)
        api_get("/v1/orders/#{seg(id, :id)}/payment", Models::OrderPayment, options: options)
      end

      # Documents of an order (GET /v1/orders/:id/documents).
      #
      # @param id [String] the +external_order_id+
      # @param options [Hash, nil]
      # @return [Models::OrderDocuments]
      def list_documents(id, options: nil)
        api_get("/v1/orders/#{seg(id, :id)}/documents", Models::OrderDocuments, options: options)
      end

      # Short-lived download URL for one document (GET /v1/orders/:id/documents/:documentId/download).
      #
      # @param id [String] the +external_order_id+
      # @param document_id [String]
      # @param options [Hash, nil]
      # @return [Models::DocumentDownloadUrl]
      def get_document_download(id, document_id, options: nil)
        api_get("/v1/orders/#{seg(id, :id)}/documents/#{seg(document_id, :document_id)}/download", Models::DocumentDownloadUrl,
                options: options)
      end
    end
  end
end
