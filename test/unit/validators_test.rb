# frozen_string_literal: true

require 'test_helper'

class ValidatorsTest < Minitest::Test
  V = StampMitra::Validators

  METHODS = { 'pan' => :pan, 'gstin' => :gstin, 'ifsc' => :ifsc, 'cin' => :cin, 'udyam' => :udyam, 'vehicleNumber' => :vehicle_number,
              'bankAccount' => :bank_account, 'passport' => :passport_file_number, 'drivingLicense' => :driving_license,
              'voterId' => :voter_id }.freeze

  vectors = TestHelper.json('validators.json')['validators']
  vectors.each do |name, definition|
    definition['valid'].each_with_index do |input, i|
      define_method("test_#{name}_valid_#{i}") do
        out = V.public_send(METHODS.fetch(name), input)
        trim_only = definition['normalization'] == 'trim only'
        expected = trim_only ? input.strip : input.strip.upcase
        assert_equal expected, out
        assert_match Regexp.new(definition['pattern']), out
      end
    end
    definition['invalid'].each_with_index do |input, i|
      define_method("test_#{name}_invalid_#{i}") do
        error = assert_raises(StampMitra::ValidationError, input.inspect) { V.public_send(METHODS.fetch(name), input) }
        assert_equal definition['field'], error.field
        assert_nil error.status
      end
    end
  end

  def test_every_vector_group_has_a_validator
    groups = TestHelper.json('validators.json')['validators'].keys
    assert_equal groups.sort, METHODS.keys.sort
  end

  # The earlier SDKs stripped spaces/hyphens before matching; the API does not, so neither do we.
  def test_separators_are_never_stripped
    ['MH 12 AB 1234', 'MH-12-AB-1234'].each { |v| assert_raises(StampMitra::ValidationError) { V.vehicle_number(v) } }
    ['PA 1079341954215', 'PA-1079341954215'].each { |v| assert_raises(StampMitra::ValidationError) { V.passport_file_number(v) } }
    ['MH-14-2011-0012345', 'MH14 20110012345'].each { |v| assert_raises(StampMitra::ValidationError) { V.driving_license(v) } }
    ['1234 5678 9012', '1234-5678-9012'].each { |v| assert_raises(StampMitra::ValidationError) { V.bank_account(v) } }
  end

  def test_regex_anchors_reject_trailing_and_embedded_newlines
    %W[ABCDE1234F ABCDE1234F\nX X\nABCDE1234F ABC\nDE1234F].each_with_index do |input, i|
      next if i.zero?

      assert_raises(StampMitra::ValidationError, input.inspect) { V.pan(input) }
    end
  end

  def test_non_string_and_invalid_encoding_inputs_are_rejected
    [nil, 123_456_789, :pan, ['ABCDE1234F'], 1.5].each { |v| assert_raises(StampMitra::ValidationError, v.inspect) { V.pan(v) } }
    assert_raises(StampMitra::ValidationError) { V.pan("ABCDE123\xFF".dup.force_encoding('UTF-8')) }
    assert_raises(StampMitra::ValidationError) { V.bank_account(123_456_789_012) }
  end

  def test_upcase_is_ascii_only
    assert_raises(StampMitra::ValidationError) { V.pan('ſBCDE1234F') } # long s would upcase to S under full Unicode casing
  end

  def test_unicode_whitespace_is_trimmed
    assert_equal 'ABCDE1234F', V.pan(' ABCDE1234F ')
  end

  def test_phone
    ['9876543210', '+919876543210', '919876543210', '09876543210'].each { |v| assert_equal v, V.phone(v) }
    %w[1234567890 98765 98765432101 abcdefghij].each { |v| assert_raises(StampMitra::ValidationError, v) { V.phone(v) } }
  end

  def test_dates
    assert_equal '1990-01-31', V.date('1990-01-31')
    assert_equal '1990-01-31', V.date(' 1990-01-31 ')
    assert_equal '1990-01-31T00:00:00Z', V.date('1990-01-31T00:00:00Z')
    assert_equal '1990-01-31', V.date(Date.new(1990, 1, 31))
    assert_equal '1990-01-31', V.date(Time.utc(1990, 1, 31, 12))
    ['31-01-1990', '1990/01/31', '1990-13-01', '1990-02-30', '', 'yesterday', nil, 19_900_131].each do |bad|
      assert_raises(StampMitra::ValidationError, bad.inspect) { V.date(bad) }
    end
  end

  def test_names
    assert_equal 'Rahul Kumar', V.name('  Rahul Kumar ')
    assert_equal 256, V.name('a' * 256).length
    ['', '   ', 'a' * 257, nil].each { |bad| assert_raises(StampMitra::ValidationError) { V.name(bad) } }
  end

  def test_resource_methods_validate_before_sending
    adapter = FakeAdapter.new
    client = fake_client(adapter)
    calls = [
      -> { client.verify.gstin(gstin: '22ABCDE1234F0Z5') }, -> { client.verify.rc(vehicle_number: 'MH 12 AB 1234') },
      -> { client.verify.voter_id(voter_id: 'AB1234567') }, -> { client.verify.driving_license(dl_number: 'MH1420110012345', dob: '31-01-1990') },
      -> { client.verify.passport(file_number: 'PA-1', dob: '1990-01-31') }, -> { client.verify.cin(cin: 'X') },
      -> { client.verify.udyam(udyam_number: 'UDYAM-MH-1-1') }, -> { client.verify.pan_to_gstin(pan: '') }, -> { client.verify.pan_to_udyam(pan: 'x') },
      -> { client.verify.bank_account(account_number: '123', ifsc: 'ICIC0001234') }, -> { client.verify.bank_account(account_number: '123456789', ifsc: 'bad') },
      -> { client.verify.bank_account(account_number: '123456789', ifsc: 'ICIC0001234', phone: '123') }, -> { client.verify.pan(pan: 'ABCDE1234F', name: '') },
      -> { client.orders.create(external_order_id: '', external_customer_id: 'c', service_code: 's') },
      -> { client.orders.create(external_order_id: 'o', external_customer_id: nil, service_code: 's') },
      -> { client.payments.intents.create(external_order_id: 'o', amount_minor: 1.5, currency: 'INR', payment_connection_id: 'p') },
      -> { client.payments.intents.create(external_order_id: 'o', amount_minor: 0, currency: 'INR', payment_connection_id: 'p') },
      -> { client.estamp.calculate_duty(state_code: '', article_code: '5', stamp_duty_amount: 1) },
      -> { client.estamp.calculate_duty(state_code: 'MH', article_code: '5', stamp_duty_amount: -1) },
      -> { client.logs.list(status: 'maybe') }, -> { client.logs.list(limit: 0) }, -> { client.logs.list(limit: 201) }, -> { client.logs.list(limit: '5') },
      -> { client.webhooks.events.list(limit: 0) }
    ]
    calls.each_with_index { |call, i| assert_raises(StampMitra::ValidationError, "call #{i}") { call.call } }
    assert_empty adapter.calls
  end

  def test_normalised_values_are_what_gets_sent
    adapter = FakeAdapter.new
    client = fake_client(adapter)
    client.verify.gstin(gstin: ' 27aabct1332l1zz ')
    client.verify.driving_license(dl_number: 'mh1420110012345', dob: Date.new(1990, 1, 31))
    assert_equal({ 'gstin' => '27AABCT1332L1ZZ' }, adapter.bodies[0])
    assert_equal({ 'dlNumber' => 'MH1420110012345', 'dob' => '1990-01-31' }, adapter.bodies[1])
  end
end
