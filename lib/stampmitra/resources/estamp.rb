# frozen_string_literal: true

module StampMitra
  module Resources
    # e-Stamp Paper reference data and helpers (+client.estamp+). The API proxies
    # these from an upstream service and does not fix their shape, so responses are
    # {Models::GenericResponse} objects (+#[]+, +#to_h+, +#items+).
    class Estamp < Base
      # @return [EstampOrders] typed e-Stamp orders (+client.estamp.orders+)
      attr_reader :orders
      # @return [EstampStamps] stamps of an order (+client.estamp.stamps+)
      attr_reader :stamps

      # @param transport [Transport]
      # @param options [Hash] +validate_input:+ and +with_response:+
      def initialize(transport, **options)
        super
        @orders = EstampOrders.new(transport, **options)
        @stamps = EstampStamps.new(transport, **options)
      end

      # Availability of every state (GET /v1/estamp/states/availability).
      #
      # @param active [Boolean, nil] only active (+true+) or inactive (+false+) states
      # @param options [Hash, nil]
      # @return [Models::EstampStatesAvailability]
      def get_states_availability(active: nil, options: nil)
        api_get('/v1/estamp/states/availability', Models::EstampStatesAvailability, query: { active: active }, options: options)
      end

      # One state with its rules and flags (GET /v1/estamp/states/:stateCode).
      #
      # @param state_code [String] e.g. "MH"
      # @param options [Hash, nil]
      # @return [Models::EstampState]
      def get_state(state_code, options: nil)
        api_get("/v1/estamp/states/#{seg(state_code, :state_code)}", Models::EstampState, options: options)
      end

      # Field requirements of a state, optionally narrowed to an article, a denomination and a category, with a generated
      # +example_body+ (GET /v1/estamp/states/:stateCode/requirements).
      #
      # @param state_code [String]
      # @param article_code [String, nil] max 60 characters
      # @param denomination [Numeric, nil] rupees, greater than 0
      # @param category [String, Symbol, nil] "e_stamp" or "traditional_stamp"
      # @param options [Hash, nil]
      # @return [Models::EstampRequirements]
      def get_state_requirements(state_code, article_code: nil, denomination: nil, category: nil, options: nil)
        category = category&.to_s
        check_requirements_query(article_code, denomination, category) if validate?
        query = { articleCode: article_code, denomination: denomination, category: category }
        api_get("/v1/estamp/states/#{seg(state_code, :state_code)}/requirements", Models::EstampRequirements, query: query, options: options)
      end

      # Districts of a state (GET /v1/estamp/states/:stateCode/districts).
      #
      # @param state_code [String]
      # @param options [Hash, nil]
      # @return [Models::EstampDistrictList] enumerable of {Models::EstampDistrict}
      def list_districts(state_code, options: nil)
        api_get("/v1/estamp/states/#{seg(state_code, :state_code)}/districts", Models::EstampDistrictList, options: options)
      end

      # Sub-registrar offices of a district (GET /v1/estamp/states/:stateCode/districts/:districtCode/sros).
      #
      # @param state_code [String]
      # @param district_code [String]
      # @param options [Hash, nil]
      # @return [Models::EstampSroList] enumerable of {Models::EstampSro}; send an office's +value+ as +sro+ of a stamp line
      def list_sros(state_code, district_code, options: nil)
        api_get("/v1/estamp/states/#{seg(state_code, :state_code)}/districts/#{seg(district_code, :district_code)}/sros",
                Models::EstampSroList, options: options)
      end

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

      private

      def check_requirements_query(article_code, denomination, category)
        unless article_code.nil? || (article_code.is_a?(String) && article_code.length <= 60)
          raise ValidationError.for_field('articleCode', 'articleCode must be a String of at most 60 characters')
        end
        unless denomination.nil? || (denomination.is_a?(Numeric) && denomination.positive?)
          raise ValidationError.for_field('denomination', 'denomination must be a number greater than 0')
        end
        return if category.nil? || EstampOrderInput::CATEGORIES.include?(category)

        raise ValidationError.for_field('category', "category must be one of #{EstampOrderInput::CATEGORIES.join(', ')}")
      end
    end
  end
end
