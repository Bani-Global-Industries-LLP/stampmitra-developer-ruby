# frozen_string_literal: true

module StampMitra
  # One party to an instrument. Pass it (or a bare name String) as +first_party+ / +second_party+ of an {EstampStampLine}.
  # Use the object form whenever the state wants an address or a father's or husband's name.
  #
  #   StampMitra::EstampParty.new(name: 'Jane Doe', address: '12 MG Road, Pune', gender: 'FEMALE')
  #
  # Members: +name+ (required, 1-150 characters), +address+ (max 500), +phone+ (max 20), +father_husband_name+ (max 150)
  # and +gender+ (+MALE+, +FEMALE+ or +OTHER+).
  EstampParty = Struct.new(:name, :address, :phone, :father_husband_name, :gender, keyword_init: true) do
    # @return [Hash{String => Object}] the JSON object sent to the API (camelCase keys, nil members left out)
    def to_h
      { 'name' => name, 'address' => address, 'phone' => phone, 'fatherHusbandName' => father_husband_name,
        'gender' => gender }.compact
    end
  end

  # Property area of a stamp line. +unit+ is exactly one of +Square Feet+, +Square Yard+, +Square Meters+ or
  # +Not Applicable+; +value+ (greater than 0) is required unless the unit is +Not Applicable+.
  EstampPropertyArea = Struct.new(:unit, :value, keyword_init: true) do
    # @return [Hash{String => Object}] the JSON object sent to the API
    def to_h
      { 'unit' => unit, 'value' => value }.compact
    end
  end

  # One stamp line of an e-Stamp order (+stamps[]+ of {Resources::EstampOrders#validate} / {Resources::EstampOrders#create}).
  # Plain Hashes (snake_case or camelCase keys) are accepted wherever an {EstampStampLine} is.
  #
  # Required: +state+, +article_code+, +denomination+ (rupees, greater than 0) and +first_party+. Optional: +category+
  # (+e_stamp+ or +traditional_stamp+), +quantity+ (1 to 1000), +second_party+, +stamp_duty_payer+, +payer_phone+,
  # +payer_gender+, +purpose+, +district+, +sro+, +cess_amount+, +property_area+, +pan_card_image+ (an +https://+ link; optional
  # when placing the order, but a PAN card is mandatory to complete the stamp), +client_reference+, +cost_centre+,
  # +business_unit+ and +linked_doc_ref+.
  EstampStampLine = Struct.new(
    :client_reference, :state, :category, :article_code, :denomination, :stamp_duty_payer, :payer_phone, :payer_gender,
    :first_party, :second_party, :purpose, :district, :sro, :cess_amount, :property_area, :pan_card_image, :cost_centre,
    :business_unit, :linked_doc_ref, :quantity, keyword_init: true
  ) do
    # @return [Hash{String => Object}] the JSON object sent to the API (camelCase keys, nil members left out)
    def to_h
      each_pair.with_object({}) do |(key, value), out|
        out[EstampOrderInput.camelize(key.to_s)] = EstampOrderInput.wire_value(value) unless value.nil?
      end
    end
  end

  # Normalises and checks the body of an e-Stamp order. Not part of the public API.
  # @api private
  module EstampOrderInput
    CATEGORIES = %w[e_stamp traditional_stamp].freeze
    GENDERS = %w[MALE FEMALE OTHER].freeze
    UNITS = ['Square Feet', 'Square Yard', 'Square Meters', 'Not Applicable'].freeze
    MAX_STAMPS = 5000
    MAX_QUANTITY = 1000

    module_function

    # @return [String] snake_case to camelCase (already camelCase input is unchanged)
    def camelize(name)
      head, *rest = name.split('_')
      head + rest.map(&:capitalize).join
    end

    # Converts structs and Hashes (any key style) to JSON-ready values.
    def wire_value(value)
      case value
      when EstampParty, EstampPropertyArea, EstampStampLine then value.to_h
      when Hash then value.each_with_object({}) { |(k, v), out| out[camelize(k.to_s)] = wire_value(v) unless v.nil? }
      when Array then value.map { |v| wire_value(v) }
      else value
      end
    end

    # @return [Array<Hash>] wire stamp lines
    def lines(stamps)
      if stamps.is_a?(Array)
        stamps.map { |line| line.is_a?(EstampStampLine) || line.is_a?(Hash) ? wire_value(line) : line }
      else
        stamps
      end
    end

    # Raises a {ValidationError} carrying every finding as +error.errors+ (same shape as the API's +details.errors+).
    def check!(stamps)
      issues = []
      validate_list(stamps, issues)
      return if issues.empty?

      text = issues.map { |idx| "#{idx['field']}: #{idx['message']}" }.join('; ')
      raise ValidationError.new("VALIDATION_FAILED: #{text}", code: 'VALIDATION_ERROR', field: issues.first['field'],
                                                              details: { 'errors' => issues })
    end

    def issue(issues, field, code, message, index = nil)
      issues << { 'field' => field, 'code' => code, 'message' => message, 'index' => index }.compact
    end

    def validate_list(stamps, issues)
      return issue(issues, 'stamps', 'REQUIRED', 'stamps must be a non-empty array') unless stamps.is_a?(Array) && !stamps.empty?
      return issue(issues, 'stamps', 'TOO_MANY', "stamps holds at most #{MAX_STAMPS} lines") if stamps.size > MAX_STAMPS

      stamps.each_with_index { |line, idx| validate_line(line, idx, issues) }
      states = stamps.filter_map { |line| line['state'].to_s.strip.upcase if line.is_a?(Hash) && line['state'].is_a?(String) }.uniq
      return unless states.size > 1

      first = stamps.index { |line| line.is_a?(Hash) && line['state'].to_s.strip.upcase != states.first }
      issue(issues, "stamps[#{first}].state", 'MIXED_STATE', 'all stamp lines of one order must be in the same state', first)
    end

    def validate_line(line, idx, issues)
      path = "stamps[#{idx}]"
      return issue(issues, path, 'INVALID_TYPE', 'a stamp line must be an object', idx) unless line.is_a?(Hash)

      %w[state articleCode].each { |key| require_text(line, key, path, idx, issues) }
      validate_denomination(line, path, idx, issues)
      validate_enum(line['category'], CATEGORIES, "#{path}.category", idx, issues)
      validate_enum(line['payerGender'], GENDERS, "#{path}.payerGender", idx, issues)
      validate_party(line['firstParty'], "#{path}.firstParty", idx, issues, required: true)
      validate_party(line['secondParty'], "#{path}.secondParty", idx, issues, required: false)
      validate_area(line['propertyArea'], "#{path}.propertyArea", idx, issues)
      validate_link(line['panCardImage'], "#{path}.panCardImage", idx, issues)
      validate_quantity(line['quantity'], "#{path}.quantity", idx, issues)
    end

    def require_text(hash, key, path, idx, issues)
      value = hash[key]
      return if value.is_a?(String) && !value.strip.empty?

      issue(issues, "#{path}.#{key}", value.nil? ? 'REQUIRED' : 'INVALID_TYPE', "#{key} is required and must be a non-empty string", idx)
    end

    def validate_denomination(line, path, idx, issues)
      value = line['denomination']
      return issue(issues, "#{path}.denomination", 'REQUIRED', 'denomination is required', idx) if value.nil?
      return issue(issues, "#{path}.denomination", 'INVALID_TYPE', 'denomination must be a number', idx) unless value.is_a?(Numeric)

      issue(issues, "#{path}.denomination", 'OUT_OF_RANGE', 'denomination must be greater than 0', idx) unless value.positive?
    end

    def validate_enum(value, allowed, field, idx, issues)
      return if value.nil? || allowed.include?(value)

      issue(issues, field, 'INVALID_VALUE', "must be one of #{allowed.join(', ')}", idx)
    end

    def validate_party(party, field, idx, issues, required:)
      return issue(issues, field, 'REQUIRED', 'a first party is required', idx) if party.nil? && required
      return if party.nil?
      return issue(issues, field, 'PARTY_MUST_BE_OBJECT', 'send a name string or one party object, not an array', idx) if party.is_a?(Array)

      party = { 'name' => party } if party.is_a?(String)
      return issue(issues, field, 'INVALID_TYPE', 'a party is a name string or an object', idx) unless party.is_a?(Hash)

      validate_party_object(party, field, idx, issues)
    end

    def validate_party_object(party, field, idx, issues)
      name = party['name']
      if !name.is_a?(String) || name.strip.empty?
        issue(issues, "#{field}.name", 'REQUIRED', 'name is required', idx)
      elsif name.length > 150
        issue(issues, "#{field}.name", 'TOO_LONG', 'name is at most 150 characters', idx)
      end
      { 'address' => 500, 'phone' => 20, 'fatherHusbandName' => 150 }.each do |key, max|
        issue(issues, "#{field}.#{key}", 'TOO_LONG', "#{key} is at most #{max} characters", idx) if party[key].to_s.length > max
      end
      validate_enum(party['gender'], GENDERS, "#{field}.gender", idx, issues)
    end

    def validate_area(area, field, idx, issues)
      return if area.nil?
      return issue(issues, field, 'INVALID_TYPE', 'propertyArea is an object { unit, value }', idx) unless area.is_a?(Hash)
      return issue(issues, "#{field}.unit", 'INVALID_UNIT', "unit must be one of #{UNITS.join(', ')}", idx) unless UNITS.include?(area['unit'])
      return if area['unit'] == 'Not Applicable'

      value = area['value']
      issue(issues, "#{field}.value", 'OUT_OF_RANGE', 'value must be a number greater than 0', idx) unless value.is_a?(Numeric) && value.positive?
    end

    def validate_link(link, field, idx, issues)
      return if link.nil?
      return issue(issues, field, 'INVALID_TYPE', 'panCardImage must be a string', idx) unless link.is_a?(String)
      return issue(issues, field, 'HTTPS_URL_REQUIRED', 'panCardImage must be an https:// link', idx) unless link.start_with?('https://')

      issue(issues, field, 'TOO_LONG', 'panCardImage is at most 2048 characters', idx) if link.length > 2048
    end

    def validate_quantity(quantity, field, idx, issues)
      return if quantity.nil?
      return if quantity.is_a?(Integer) && quantity.between?(1, MAX_QUANTITY)

      issue(issues, field, 'OUT_OF_RANGE', "quantity must be an Integer from 1 to #{MAX_QUANTITY}", idx)
    end
  end
end
