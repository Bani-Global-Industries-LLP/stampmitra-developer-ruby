# frozen_string_literal: true

require 'json'

module StampMitra
  # Masks credentials and personal data before anything reaches a logger or an
  # +inspect+ string. Used by the debug logger and by response models.
  module Redaction
    # Placeholder for removed values.
    REDACTED = '[REDACTED]'

    # Header names (lower-case) whose values are always replaced.
    SECRET_HEADERS = %w[authorization x-api-key cookie set-cookie proxy-authorization].freeze

    # Keys (normalised: lower-case, no "_" or "-") whose values are identifiers; the last four characters stay visible.
    IDENTIFIER_KEYS = %w[
      pan gstin accountnumber ifsc cin udyamnumber vehiclenumber regno dlnumber filenumber voterid phone
      din chassis engine micr utr email customermobile customeremail partypan providerintentid
    ].freeze

    # Keys whose values are personal data and are removed entirely.
    PERSONAL_KEYS = %w[
      name businessname registeredname fathername ownername ownerfathername nameatbank fatherorhusbandname
      companyname tradename legalname dob address principalplaceofbusiness enterprisename customername
      partyname partyaddress
    ].freeze

    # Matches API keys (sk_test_... / sk_live_...) inside free text.
    API_KEY_PATTERN = /sk_(?:test|live)_[A-Za-z0-9_-]+/
    # Matches a PAN inside free text.
    PAN_PATTERN = /\b[A-Z]{5}[0-9]{4}[A-Z]\b/
    # Matches a GSTIN inside free text.
    GSTIN_PATTERN = /\b[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b/

    module_function

    # Redacts secret headers (Authorization, x-api-key, cookies...).
    #
    # @param headers [Hash{String => String, Array<String>}]
    # @return [Hash{String => String}]
    def headers(headers)
      headers.each_with_object({}) do |(name, value), out|
        out[name.to_s] = SECRET_HEADERS.include?(name.to_s.downcase) ? REDACTED : Array(value).join(', ')
      end
    end

    # Recursively masks identifiers and removes personal data from parsed JSON.
    #
    # @param data [Object] Hash, Array or scalar
    # @return [Object] a masked copy
    def mask(data)
      case data
      when Hash then data.each_with_object({}) { |(key, value), out| out[key] = mask_pair(key, value) }
      when Array then data.map { |item| mask(item) }
      when String then scrub(data)
      else data
      end
    end

    # Masks a JSON body for logging; non-JSON text is replaced with a length marker.
    #
    # @param body [String, nil]
    # @return [String]
    def body(body)
      return '' if body.nil? || body.empty?

      parsed = JSON.parse(body)
      return "[non-JSON body, #{body.bytesize} bytes]" unless parsed.is_a?(Hash) || parsed.is_a?(Array)

      JSON.generate(mask(parsed))
    rescue JSON::ParserError
      "[non-JSON body, #{body.bytesize} bytes]"
    end

    # Replaces API keys, PANs and GSTINs found anywhere inside free text.
    #
    # @param text [String]
    # @return [String]
    def scrub(text)
      text.gsub(API_KEY_PATTERN, REDACTED).gsub(GSTIN_PATTERN) { |m| keep_last_four(m) }.gsub(PAN_PATTERN) { |m| keep_last_four(m) }
    end

    # Replaces only API keys (sk_test_... / sk_live_...) found in free text.
    #
    # @param text [String]
    # @return [String]
    def scrub_keys(text)
      text.gsub(API_KEY_PATTERN, REDACTED)
    end

    # @api private
    def mask_pair(key, value)
      normalised = key.to_s.downcase.delete('_-')
      if PERSONAL_KEYS.include?(normalised) && !value.nil?
        REDACTED
      elsif IDENTIFIER_KEYS.include?(normalised) && (value.is_a?(String) || value.is_a?(Numeric))
        keep_last_four(value.to_s)
      else
        mask(value)
      end
    end

    # @api private
    def keep_last_four(text)
      text.length > 4 ? ('*' * (text.length - 4)) + text[-4..] : '****'
    end
  end
end
