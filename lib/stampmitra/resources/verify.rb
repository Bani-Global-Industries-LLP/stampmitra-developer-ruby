# frozen_string_literal: true

module StampMitra
  module Resources
    # Identity verification (+client.verify+). Every call is metered, including
    # negative results (+valid: false+ is still a success response and is billed).
    # An Idempotency-Key is generated per call and reused across automatic
    # retries, so a retry replays the original result instead of billing twice.
    #
    # Every method accepts +options:+ (see :Client): +timeout+, +max_retries+,
    # +idempotency_key+ and +headers+.
    class Verify < Base
      # Shorthand for {StampMitra::Validators}.
      V = Validators

      # Verifies a PAN (POST /v1/verify/pan).
      #
      # @param pan [String] e.g. "ABCDE1234F"
      # @param name [String, nil] name to cross-check against the PAN record
      # @param options [Hash, nil]
      # @return [Models::PanVerification]
      def pan(pan:, name: nil, options: nil)
        if validate?
          pan = V.pan(pan)
          name = V.name(name) unless name.nil?
        end
        api_post('/v1/verify/pan', Models::PanVerification, { 'pan' => pan, 'name' => name }, options: options)
      end

      # Verifies a GSTIN (POST /v1/verify/gstin).
      #
      # @param gstin [String] 15 character GSTIN
      # @param business_name [String, nil]
      # @param options [Hash, nil]
      # @return [Models::GstinVerification]
      def gstin(gstin:, business_name: nil, options: nil)
        if validate?
          gstin = V.gstin(gstin)
          business_name = V.name(business_name, field: 'businessName') unless business_name.nil?
        end
        api_post('/v1/verify/gstin', Models::GstinVerification, { 'gstin' => gstin, 'businessName' => business_name }, options: options)
      end

      # Verifies a vehicle registration certificate (POST /v1/verify/rc).
      #
      # @param vehicle_number [String] e.g. "MH12AB1234" (no separators)
      # @param options [Hash, nil]
      # @return [Models::RcVerification]
      def rc(vehicle_number:, options: nil)
        vehicle_number = V.vehicle_number(vehicle_number) if validate?
        api_post('/v1/verify/rc', Models::RcVerification, { 'vehicleNumber' => vehicle_number }, options: options)
      end

      # Verifies a voter ID / EPIC number (POST /v1/verify/voter-id).
      #
      # @param voter_id [String] e.g. "ABC1234567"
      # @param name [String, nil]
      # @param options [Hash, nil]
      # @return [Models::VoterIdVerification]
      def voter_id(voter_id:, name: nil, options: nil)
        if validate?
          voter_id = V.voter_id(voter_id)
          name = V.name(name) unless name.nil?
        end
        api_post('/v1/verify/voter-id', Models::VoterIdVerification, { 'voterId' => voter_id, 'name' => name }, options: options)
      end

      # Verifies a driving licence (POST /v1/verify/driving-license). Needs an
      # IP-allowlisted key; otherwise a :PermissionDeniedError carries the server message.
      #
      # @param dl_number [String] e.g. "MH1420110012345"
      # @param dob [String, Date, Time] date of birth, ISO 8601 (YYYY-MM-DD)
      # @param options [Hash, nil]
      # @return [Models::DrivingLicenseVerification]
      def driving_license(dl_number:, dob:, options: nil)
        if validate?
          dl_number = V.driving_license(dl_number)
          dob = V.date(dob)
        end
        api_post('/v1/verify/driving-license', Models::DrivingLicenseVerification, { 'dlNumber' => dl_number, 'dob' => date_string(dob) },
                 options: options)
      end

      # Verifies a passport application (POST /v1/verify/passport). Needs an
      # IP-allowlisted key; otherwise a :PermissionDeniedError carries the server message.
      #
      # @param file_number [String] passport application file number, e.g. "PA1079341954215"
      # @param dob [String, Date, Time] date of birth, ISO 8601 (YYYY-MM-DD)
      # @param name [String, nil]
      # @param options [Hash, nil]
      # @return [Models::PassportVerification]
      def passport(file_number:, dob:, name: nil, options: nil)
        if validate?
          file_number = V.passport_file_number(file_number)
          dob = V.date(dob)
          name = V.name(name) unless name.nil?
        end
        api_post('/v1/verify/passport', Models::PassportVerification, { 'fileNumber' => file_number, 'dob' => date_string(dob), 'name' => name },
                 options: options)
      end

      # Verifies a company identification number (POST /v1/verify/cin).
      #
      # @param cin [String] e.g. "U74999DL2015PTC284009"
      # @param options [Hash, nil]
      # @return [Models::CinVerification]
      def cin(cin:, options: nil)
        cin = V.cin(cin) if validate?
        api_post('/v1/verify/cin', Models::CinVerification, { 'cin' => cin }, options: options)
      end

      # Verifies a Udyam registration number (POST /v1/verify/udyam).
      #
      # @param udyam_number [String] e.g. "UDYAM-MH-12-1234567"
      # @param options [Hash, nil]
      # @return [Models::UdyamVerification]
      def udyam(udyam_number:, options: nil)
        udyam_number = V.udyam(udyam_number) if validate?
        api_post('/v1/verify/udyam', Models::UdyamVerification, { 'udyamNumber' => udyam_number }, options: options)
      end

      # Finds the GSTINs registered against a PAN (POST /v1/verify/pan-to-gstin).
      #
      # @param pan [String]
      # @param options [Hash, nil]
      # @return [Models::PanToGstin]
      def pan_to_gstin(pan:, options: nil)
        pan = V.pan(pan) if validate?
        api_post('/v1/verify/pan-to-gstin', Models::PanToGstin, { 'pan' => pan }, options: options)
      end

      # Finds the Udyam registration linked to a PAN (POST /v1/verify/pan-to-udyam).
      #
      # @param pan [String]
      # @param options [Hash, nil]
      # @return [Models::PanToUdyam]
      def pan_to_udyam(pan:, options: nil)
        pan = V.pan(pan) if validate?
        api_post('/v1/verify/pan-to-udyam', Models::PanToUdyam, { 'pan' => pan }, options: options)
      end

      # Verifies a bank account (POST /v1/verify/bank-account).
      #
      # @param account_number [String] 9-18 digits, kept as a String to preserve leading zeros
      # @param ifsc [String] e.g. "ICIC0001234"
      # @param name [String, nil] name to cross-check against the account holder
      # @param phone [String, nil] holder's Indian mobile number, improves match confidence
      # @param options [Hash, nil]
      # @return [Models::BankAccountVerification]
      def bank_account(account_number:, ifsc:, name: nil, phone: nil, options: nil)
        if validate?
          account_number = V.bank_account(account_number)
          ifsc = V.ifsc(ifsc)
          name = V.name(name) unless name.nil?
          phone = V.phone(phone) unless phone.nil?
        end
        api_post('/v1/verify/bank-account', Models::BankAccountVerification,
                 { 'accountNumber' => account_number, 'ifsc' => ifsc, 'name' => name, 'phone' => phone }, options: options)
      end

      private

      def date_string(value)
        value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d') : value
      end
    end
  end
end
