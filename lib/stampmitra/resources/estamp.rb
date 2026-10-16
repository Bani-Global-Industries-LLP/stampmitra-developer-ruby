# frozen_string_literal: true

module StampMitra
  module Resources
    # e-Stamp Paper reference data and helpers (+client.estamp+). The API proxies
    # these from an upstream service and does not fix their shape, so responses are
    # {Models::GenericResponse} objects (+#[]+, +#to_h+, +#items+).
    class Estamp < Base
      # Field schema for a service (GET /v1/estamp/schema/:serviceCode).
      #
      # @param service_code [String] e.g. "estamp.instrument.rent_agreement"
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def get_schema(service_code, options: nil)
        api_get("/v1/estamp/schema/#{seg(service_code, :service_code)}", Models::GenericResponse, options: options)
      end

      # e-Stamp-eligible states (GET /v1/estamp/states).
      #
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def list_states(options: nil)
        api_get('/v1/estamp/states', Models::GenericResponse, options: options)
      end

      # Instruments available in a state (GET /v1/estamp/states/:stateCode/instruments).
      #
      # @param state_code [String] e.g. "MH"
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def list_instruments(state_code, options: nil)
        api_get("/v1/estamp/states/#{seg(state_code, :state_code)}/instruments", Models::GenericResponse, options: options)
      end

      # Articles of an instrument (GET /v1/estamp/instruments/:instrumentCode/articles).
      #
      # @param instrument_code [String]
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def list_articles(instrument_code, options: nil)
        api_get("/v1/estamp/instruments/#{seg(instrument_code, :instrument_code)}/articles", Models::GenericResponse, options: options)
      end

      # Calculates stamp duty (POST /v1/estamp/duty/calculate). Metered.
      #
      # @param state_code [String]
      # @param article_code [String]
      # @param stamp_duty_amount [Numeric]
      # @param district_code [String, nil]
      # @param sro_value [String, nil]
      # @param doorstep_delivery [Boolean, nil]
      # @param coupon_code [String, nil]
      # @param master_data_version [Integer, nil]
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def calculate_duty(state_code:, article_code:, stamp_duty_amount:, district_code: nil, sro_value: nil,
                         doorstep_delivery: nil, coupon_code: nil, master_data_version: nil, options: nil)
        if validate?
          require_string!(state_code, 'stateCode')
          require_string!(article_code, 'articleCode')
          unless stamp_duty_amount.is_a?(Numeric) && stamp_duty_amount >= 0
            raise ValidationError.for_field('stampDutyAmount', 'stampDutyAmount must be a non-negative number')
          end
        end
        body = { 'stateCode' => state_code, 'articleCode' => article_code, 'stampDutyAmount' => stamp_duty_amount,
                 'districtCode' => district_code, 'sroValue' => sro_value, 'doorstepDelivery' => doorstep_delivery,
                 'couponCode' => coupon_code, 'masterDataVersion' => master_data_version }
        api_post('/v1/estamp/duty/calculate', Models::GenericResponse, body, options: options)
      end

      # Adds the parties to an e-Stamp order (POST /v1/estamp/orders/:orderId/parties). Metered.
      # An Idempotency-Key is generated automatically (and reused across retries) unless you pass one.
      #
      # @param order_id [String] the +external_order_id+ of the order
      # @param customer_name [String, nil]
      # @param party_name [String, nil]
      # @param customer_mobile [String, nil]
      # @param customer_email [String, nil]
      # @param party_address [String, nil]
      # @param party_pan [String, nil]
      # @param options [Hash, nil]
      # @return [Models::GenericResponse]
      def add_parties(order_id, customer_name: nil, party_name: nil, customer_mobile: nil, customer_email: nil,
                      party_address: nil, party_pan: nil, options: nil)
        body = { 'customerName' => customer_name, 'partyName' => party_name, 'customerMobile' => customer_mobile,
                 'customerEmail' => customer_email, 'partyAddress' => party_address, 'partyPan' => party_pan }
        api_post("/v1/estamp/orders/#{seg(order_id, :order_id)}/parties", Models::GenericResponse, body, options: options)
      end
    end
  end
end
