# frozen_string_literal: true

require 'date'

module StampMitra
  # Client-side input validators. The patterns are copied from the API's DTO
  # validators (see +fixtures/validators.json+ in the spec repository), so
  # malformed input fails locally with a {ValidationError}: no network call,
  # nothing billed. Values are trimmed and upper-cased (ASCII only) before
  # matching, except bank account numbers, which are only trimmed. Separators
  # such as "MH-12 AB 1234" are rejected, exactly as the API does.
  #
  # Every method returns the normalised value or raises {ValidationError}.
  module Validators
    # Pattern for a PAN (copied from the API's DTO validators).
    PAN = /\A[A-Z]{5}[0-9]{4}[A-Z]\z/
    # Pattern for a GSTIN (copied from the API's DTO validators).
    GSTIN = /\A[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/
    # Pattern for a IFSC code (copied from the API's DTO validators).
    IFSC = /\A[A-Z]{4}0[A-Z0-9]{6}\z/
    # Pattern for a company identification number (copied from the API's DTO validators).
    CIN = /\A[LU][0-9]{5}[A-Z]{2}[0-9]{4}[A-Z]{3}[0-9]{6}\z/
    # Pattern for a Udyam registration number (copied from the API's DTO validators).
    UDYAM = /\AUDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}\z/
    # Pattern for a vehicle registration number (copied from the API's DTO validators).
    VEHICLE_NUMBER = /\A[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}\z/
    # Pattern for a bank account number (9-18 digits) (copied from the API's DTO validators).
    BANK_ACCOUNT = /\A[0-9]{9,18}\z/
    # Pattern for a passport application file number (copied from the API's DTO validators).
    PASSPORT_FILE_NUMBER = /\A[A-Z]{2}[0-9]{13}\z/
    # Pattern for a driving licence number (copied from the API's DTO validators).
    DRIVING_LICENSE = /\A[A-Z]{2}[0-9]{2}[0-9]{11}\z/
    # Pattern for a voter ID (EPIC number) (copied from the API's DTO validators).
    VOTER_ID = /\A[A-Z]{3}[0-9]{7}\z/
    # Pattern for a Indian mobile number (copied from the API's DTO validators).
    PHONE = /\A(?:\+?91|0)?[6-9][0-9]{9}\z/
    # Pattern for a ISO 8601 date, optionally with a time (copied from the API's DTO validators).
    ISO_DATE = /\A[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[T ][0-9:.]+(?:Z|[+-][0-9:]+)?)?\z/

    module_function

    # @param value [String]
    # @param field [String]
    # @return [String] normalised PAN
    def pan(value, field: 'pan')
      match(value, PAN, field, 'must match the format ABCDE1234F')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised GSTIN
    def gstin(value, field: 'gstin')
      match(value, GSTIN, field, 'must be a valid 15 character GSTIN, e.g. 27ABCDE1234F1Z5')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised IFSC
    def ifsc(value, field: 'ifsc')
      match(value, IFSC, field, 'must match the format ICIC0001234')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised CIN
    def cin(value, field: 'cin')
      match(value, CIN, field, 'must match the format U74999DL2015PTC284009')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised Udyam number
    def udyam(value, field: 'udyamNumber')
      match(value, UDYAM, field, 'must match the format UDYAM-XX-00-0000000')
    end

    # Trim + upper-case only; "MH-12 AB 1234" is rejected, like the API does.
    #
    # @param value [String]
    # @param field [String]
    # @return [String] normalised vehicle registration number
    def vehicle_number(value, field: 'vehicleNumber')
      match(value, VEHICLE_NUMBER, field, 'must be an Indian vehicle registration number, e.g. MH12AB1234')
    end

    # Trim only; spaces and hyphens are rejected.
    #
    # @param value [String]
    # @param field [String]
    # @return [String] the trimmed account number
    def bank_account(value, field: 'accountNumber')
      match(value, BANK_ACCOUNT, field, 'must be a 9-18 digit numeric bank account number', upcase: false)
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised passport application file number
    def passport_file_number(value, field: 'fileNumber')
      match(value, PASSPORT_FILE_NUMBER, field, 'must match the format PA1079341954215')
    end

    # Trim + upper-case only; "MH-14-2011-0012345" is rejected, like the API does.
    #
    # @param value [String]
    # @param field [String]
    # @return [String] normalised driving licence number
    def driving_license(value, field: 'dlNumber')
      match(value, DRIVING_LICENSE, field, 'must match the format MH1420110012345')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] normalised voter ID (EPIC number)
    def voter_id(value, field: 'voterId')
      match(value, VOTER_ID, field, 'must match the format ABC1234567')
    end

    # @param value [String]
    # @param field [String]
    # @return [String] the trimmed phone number
    def phone(value, field: 'phone')
      clean = trim(value, field)
      raise ValidationError.for_field(field, "#{field} must be a valid 10-digit Indian mobile number") unless PHONE.match?(clean)

      clean
    end

    # Accepts an ISO 8601 date string (YYYY-MM-DD, optionally with a time), a Date or a Time.
    #
    # @param value [String, Date, Time]
    # @param field [String]
    # @return [String] the ISO date string
    def date(value, field: 'dob')
      return value.strftime('%Y-%m-%d') if value.respond_to?(:strftime)

      clean = trim(value, field)
      raise ValidationError.for_field(field, "#{field} must be an ISO date, e.g. 1990-01-31") unless ISO_DATE.match?(clean) && calendar_date?(clean)

      clean
    end

    # Optional free-text name, 1-256 characters.
    #
    # @param value [String]
    # @param field [String]
    # @return [String] the trimmed name
    def name(value, field: 'name')
      clean = trim(value, field)
      raise ValidationError.for_field(field, "#{field} must be 1-256 characters") if clean.empty? || clean.length > 256

      clean
    end

    # @api private
    def match(value, pattern, field, hint, upcase: true)
      clean = trim(value, field)
      clean = clean.upcase(:ascii) if upcase
      raise ValidationError.for_field(field, "#{field} #{hint}") unless pattern.match?(clean)

      clean
    end

    # @api private
    def trim(value, field)
      raise ValidationError.for_field(field, "#{field} must be a String") unless value.is_a?(String)
      raise ValidationError.for_field(field, "#{field} must be valid UTF-8") unless value.valid_encoding?

      value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
    end

    # @api private
    def calendar_date?(text)
      year, month, day = text[0, 10].split('-').map(&:to_i)
      Date.valid_date?(year, month, day)
    end
  end
end
