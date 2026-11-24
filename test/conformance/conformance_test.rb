# frozen_string_literal: true

require 'test_helper'
require 'support/mock_server'
require 'support/scenarios'
require 'support/spec_coverage'
require 'securerandom'
require 'stringio'

# Black-box conformance run against the spec repository's mock server (scripts/mock-server.mjs), plus a real
# loopback server for bodies and failures the mock cannot produce. See test/support/mock_server.rb for how the
# mock is located. Every connection is a fresh one (Connection: close, Net::HTTP retries disabled), so a replayed
# request can never consume a scripted mock step unnoticed.
class ConformanceTest < Minitest::Test
  include Scenarios

  OPS = {
    'POST /v1/verify/pan' => ->(c, o) { c.verify.pan(pan: 'ABCDE1234F', name: 'Rahul Kumar', options: o) },
    'POST /v1/verify/gstin' => ->(c, o) { c.verify.gstin(gstin: '27ABCDE1234F1Z5', options: o) },
    'POST /v1/verify/rc' => ->(c, o) { c.verify.rc(vehicle_number: 'MH12AB1234', options: o) },
    'POST /v1/verify/voter-id' => ->(c, o) { c.verify.voter_id(voter_id: 'ABC1234567', options: o) },
    'POST /v1/verify/driving-license' => ->(c, o) { c.verify.driving_license(dl_number: 'MH1420110012345', dob: '1990-01-31', options: o) },
    'POST /v1/verify/passport' => ->(c, o) { c.verify.passport(file_number: 'PA1079341954215', dob: '1990-01-31', options: o) },
    'POST /v1/verify/cin' => ->(c, o) { c.verify.cin(cin: 'U74999DL2015PTC284009', options: o) },
    'POST /v1/verify/udyam' => ->(c, o) { c.verify.udyam(udyam_number: 'UDYAM-MH-12-1234567', options: o) },
    'POST /v1/verify/pan-to-gstin' => ->(c, o) { c.verify.pan_to_gstin(pan: 'ABCDE1234F', options: o) },
    'POST /v1/verify/pan-to-udyam' => ->(c, o) { c.verify.pan_to_udyam(pan: 'ABCDE1234F', options: o) },
    'POST /v1/verify/bank-account' => ->(c, o) { c.verify.bank_account(account_number: '000123456789', ifsc: 'ICIC0001234', name: 'Rahul', options: o) },
    'GET /v1/services' => ->(c, o) { c.services.list(options: o) },
    'GET /v1/services/{serviceCode}' => ->(c, o) { c.services.get('estamp.instrument.rent_agreement', options: o) },
    'GET /v1/estamp/schema/{serviceCode}' => ->(c, o) { c.estamp.get_schema('estamp.instrument.rent_agreement', options: o) },
    'GET /v1/estamp/states' => ->(c, o) { c.estamp.list_states(options: o) },
    'GET /v1/estamp/states/{stateCode}/instruments' => ->(c, o) { c.estamp.list_instruments('MH', options: o) },
    'GET /v1/estamp/instruments/{instrumentCode}/articles' => ->(c, o) { c.estamp.list_articles('rent_agreement', options: o) },
    'POST /v1/estamp/duty/calculate' => ->(c, o) { c.estamp.calculate_duty(state_code: 'MH', article_code: '5', stamp_duty_amount: 1000, options: o) },
    'POST /v1/estamp/orders/{orderId}/parties' => ->(c, o) { c.estamp.add_parties('ord_123', customer_name: 'A', party_name: 'B', options: o) },
    'POST /v1/orders' => ->(c, o) { c.orders.create(external_order_id: 'o1', external_customer_id: 'c1', service_code: 'estamp.instrument.rent_agreement', options: o) },
    'GET /v1/orders/{id}' => ->(c, o) { c.orders.get('o1', options: o) },
    'GET /v1/orders/{id}/status' => ->(c, o) { c.orders.get_status('o1', options: o) },
    'GET /v1/orders/{id}/payment' => ->(c, o) { c.orders.get_payment('o1', options: o) },
    'GET /v1/orders/{id}/documents' => ->(c, o) { c.orders.list_documents('o1', options: o) },
    'GET /v1/orders/{id}/documents/{documentId}/download' => ->(c, o) { c.orders.get_document_download('o1', 'doc_1', options: o) },
    'POST /v1/payments/intents' => lambda { |c, o|
      c.payments.intents.create(external_order_id: 'o1', amount_minor: 50_000, currency: 'INR', payment_connection_id: 'pc_1', options: o)
    },
    'GET /v1/payments/intents/{id}' => ->(c, o) { c.payments.intents.get('pi_1', options: o) },
    'GET /v1/usage/summary' => ->(c, o) { c.usage.summary(options: o) },
    'GET /v1/logs' => ->(c, o) { c.logs.list(limit: 50, options: o) },
    'GET /v1/webhooks/events' => ->(c, o) { c.webhooks.events.list(limit: 20, options: o) },
    'POST /v1/webhooks/events/{id}/replay' => ->(c, o) { c.webhooks.events.replay('evt_1', options: o) }
  }.merge(
    # ---- contract 1.2.0: the 31 e-Stamp catalogue, order, stamp, wallet and account operations ----
    'GET /v1/estamp/states/availability' => ->(c, o) { c.estamp.get_states_availability(active: true, options: o) },
    'GET /v1/estamp/states/{stateCode}' => ->(c, o) { c.estamp.get_state('MH', options: o) },
    'GET /v1/estamp/states/{stateCode}/requirements' => lambda { |c, o|
      c.estamp.get_state_requirements('MH', article_code: 'ART1', denomination: 500, category: 'e_stamp', options: o)
    },
    'GET /v1/estamp/states/{stateCode}/districts' => ->(c, o) { c.estamp.list_districts('MH', options: o) },
    'GET /v1/estamp/states/{stateCode}/districts/{districtCode}/sros' => ->(c, o) { c.estamp.list_sros('MH', 'PUNE', options: o) },
    'POST /v1/estamp/orders/validate' => ->(c, o) { c.estamp.orders.validate(**ConformanceTest.order_args, options: o) },
    'POST /v1/estamp/orders' => ->(c, o) { c.estamp.orders.create(**ConformanceTest.order_args, options: o) },
    'GET /v1/estamp/orders' => ->(c, o) { c.estamp.orders.list(page: 1, limit: 20, options: o) },
    'GET /v1/estamp/orders/{id}' => ->(c, o) { c.estamp.orders.get('estord_9c1f2a3b', options: o) },
    'POST /v1/estamp/orders/{id}/cancel' => ->(c, o) { c.estamp.orders.cancel('estord_9c1f2a3b', options: o) },
    'GET /v1/estamp/orders/{id}/export' => ->(c, o) { c.estamp.orders.export('estord_9c1f2a3b', options: o) },
    'GET /v1/estamp/orders/{id}/stamps' => ->(c, o) { c.estamp.orders.list_stamps('estord_9c1f2a3b', options: o) },
    'POST /v1/estamp/orders/{orderId}/documents' => lambda { |c, o|
      c.estamp.orders.upload_document('estord_9c1f2a3b', file: StringIO.new(ConformanceTest.pdf), filename: 'pan.pdf', type: 'pan_card', options: o)
    },
    'GET /v1/estamp/stamps/{stampId}' => ->(c, o) { c.estamp.stamps.get('eststamp_4f21ab', options: o) },
    'POST /v1/estamp/stamps/{stampId}/cancel' => ->(c, o) { c.estamp.stamps.cancel('eststamp_4f21ab', options: o) },
    'POST /v1/estamp/stamps/{stampId}/replace' => ->(c, o) { c.estamp.stamps.replace('eststamp_4f21ab', options: o) },
    'POST /v1/estamp/stamps/{stampId}/pan-card' => lambda { |c, o|
      c.estamp.stamps.set_pan_card('eststamp_4f21ab', pan_card_image: 'https://cdn.example.com/kyc/pan-4417.jpg', options: o)
    },
    'GET /v1/estamp/stamps/{stampId}/certificate' => ->(c, o) { c.estamp.stamps.get_certificate('eststamp_4f21ab', options: o) },
    'GET /v1/estamp/wallet' => ->(c, o) { c.wallets.get(options: o) },
    'GET /v1/stamp-duty-wallet' => ->(c, o) { c.wallets.stamp_duty.get_balance(options: o) },
    'POST /v1/stamp-duty-wallet/topup' => ->(c, o) { c.wallets.stamp_duty.topup(base_amount: 1000, options: o) },
    'GET /v1/stamp-duty-wallet/transactions' => ->(c, o) { c.wallets.stamp_duty.list_transactions(limit: 20, options: o) },
    'GET /v1/stamp-duty-wallet/invoices' => ->(c, o) { c.wallets.stamp_duty.list_invoices(limit: 20, options: o) },
    'GET /v1/stamp-duty-wallet/invoices/{id}' => ->(c, o) { c.wallets.stamp_duty.get_invoice('cmwtopup1234567890', options: o) },
    'GET /v1/service-fee-wallet' => ->(c, o) { c.wallets.service_fee.get_balance(options: o) },
    'POST /v1/service-fee-wallet/topup' => ->(c, o) { c.wallets.service_fee.topup(base_amount: 500, options: o) },
    'GET /v1/service-fee-wallet/transactions' => ->(c, o) { c.wallets.service_fee.list_transactions(limit: 20, options: o) },
    'GET /v1/service-fee-wallet/invoices' => ->(c, o) { c.wallets.service_fee.list_invoices(limit: 20, options: o) },
    'GET /v1/service-fee-wallet/invoices/{id}' => ->(c, o) { c.wallets.service_fee.get_invoice('inv_01HZX4K9', options: o) },
    'GET /v1/account/balance' => ->(c, o) { c.account.balance(options: o) },
    'GET /v1/account/usage' => ->(c, o) { c.account.usage(options: o) }
  ).freeze

  # Operations that take (or require) an Idempotency-Key: the SDK generates one. Every other POST sends none.
  KEYED_POSTS = %w[verify/pan verify/gstin verify/rc verify/voter-id verify/driving-license verify/passport verify/cin verify/udyam
                   verify/pan-to-gstin verify/pan-to-udyam verify/bank-account estamp/duty/calculate estamp/orders/{orderId}/parties
                   orders payments/intents estamp/orders estamp/orders/{orderId}/documents].map { |p| "POST /v1/#{p}" }.freeze

  def self.fixture_json(name)
    JSON.parse(File.read(File.join(MockServer.spec_dir, 'fixtures', 'operations', "#{name}.json"), encoding: 'UTF-8'))
  end

  # The golden order body and PAN card of the spec repository's fixtures (read lazily: the mock may be absent).
  def self.order_args
    body = fixture_json('post-v1-estamp-orders-validate.success').dig('request', 'body')
    { stamps: body['stamps'], reference: body['reference'] }
  end

  def self.pdf
    fixture_json('post-v1-estamp-orders-orderid-documents.success').dig('request', 'multipart', 'parts', 0, 'content')
  end

  SAMPLE_PATHS = {
    'GET /v1/services/{serviceCode}' => '/v1/services/estamp.instrument.rent_agreement',
    'GET /v1/estamp/schema/{serviceCode}' => '/v1/estamp/schema/estamp.instrument.rent_agreement',
    'GET /v1/estamp/states/{stateCode}/instruments' => '/v1/estamp/states/MH/instruments',
    'GET /v1/estamp/instruments/{instrumentCode}/articles' => '/v1/estamp/instruments/rent_agreement/articles',
    'POST /v1/estamp/orders/{orderId}/parties' => '/v1/estamp/orders/ord_123/parties',
    'GET /v1/orders/{id}' => '/v1/orders/o1',
    'GET /v1/orders/{id}/status' => '/v1/orders/o1/status',
    'GET /v1/orders/{id}/payment' => '/v1/orders/o1/payment',
    'GET /v1/orders/{id}/documents' => '/v1/orders/o1/documents',
    'GET /v1/orders/{id}/documents/{documentId}/download' => '/v1/orders/o1/documents/doc_1/download',
    'GET /v1/payments/intents/{id}' => '/v1/payments/intents/pi_1',
    'POST /v1/webhooks/events/{id}/replay' => '/v1/webhooks/events/evt_1/replay',
    'GET /v1/estamp/states/{stateCode}' => '/v1/estamp/states/MH',
    'GET /v1/estamp/states/{stateCode}/requirements' => '/v1/estamp/states/MH/requirements',
    'GET /v1/estamp/states/{stateCode}/districts' => '/v1/estamp/states/MH/districts',
    'GET /v1/estamp/states/{stateCode}/districts/{districtCode}/sros' => '/v1/estamp/states/MH/districts/PUNE/sros',
    'GET /v1/estamp/orders/{id}' => '/v1/estamp/orders/estord_9c1f2a3b',
    'POST /v1/estamp/orders/{id}/cancel' => '/v1/estamp/orders/estord_9c1f2a3b/cancel',
    'GET /v1/estamp/orders/{id}/export' => '/v1/estamp/orders/estord_9c1f2a3b/export',
    'GET /v1/estamp/orders/{id}/stamps' => '/v1/estamp/orders/estord_9c1f2a3b/stamps',
    'POST /v1/estamp/orders/{orderId}/documents' => '/v1/estamp/orders/estord_9c1f2a3b/documents',
    'GET /v1/estamp/stamps/{stampId}' => '/v1/estamp/stamps/eststamp_4f21ab',
    'POST /v1/estamp/stamps/{stampId}/cancel' => '/v1/estamp/stamps/eststamp_4f21ab/cancel',
    'POST /v1/estamp/stamps/{stampId}/replace' => '/v1/estamp/stamps/eststamp_4f21ab/replace',
    'POST /v1/estamp/stamps/{stampId}/pan-card' => '/v1/estamp/stamps/eststamp_4f21ab/pan-card',
    'GET /v1/estamp/stamps/{stampId}/certificate' => '/v1/estamp/stamps/eststamp_4f21ab/certificate',
    'GET /v1/stamp-duty-wallet/invoices/{id}' => '/v1/stamp-duty-wallet/invoices/cmwtopup1234567890',
    'GET /v1/service-fee-wallet/invoices/{id}' => '/v1/service-fee-wallet/invoices/inv_01HZX4K9'
  }.freeze

  def setup
    @url = MockServer.url
    MockServer.reset
    @sleeps = []
  rescue MockServer::Unavailable => e
    flunk "CONFORMANCE_REQUIRED=1 but no mock server: #{e.message}" if ENV['CONFORMANCE_REQUIRED'] == '1'
    skip e.message
  end

  def client(**options)
    StampMitra::Client.new(api_key: KEY, base_url: @url, sleeper: ->(seconds) { @sleeps << seconds }, max_retries: 2, **options)
  end

  def scenario(name)
    { headers: { 'x-mock-scenario' => name } }
  end

  def fixtures_dir
    File.join(MockServer.spec_dir, 'fixtures', 'operations')
  end

  def fixture_files
    Dir[File.join(fixtures_dir, '*.json')].map { |path| [File.basename(path), JSON.parse(File.read(path, encoding: 'UTF-8'))] }
  end

  # ---- 62 operations ---------------------------------------------------------

  def test_there_are_exactly_62_operations_and_they_match_the_spec
    assert_equal 62, OPS.size
    assert_equal SpecCoverage.spec_operations(TestHelper::ROOT), OPS.keys.map { |k| SpecCoverage.normalise(k) }.sort
  end

  def test_every_operation_hits_the_right_route_with_the_right_headers_and_returns_the_documented_body
    OPS.each do |key, call|
      MockServer.reset
      result = call.call(client, nil)
      refute_nil result, key
      seen = MockServer.recorded
      assert_equal 1, seen.size, key
      verb, template = key.split(' ', 2)
      assert_equal verb, seen[0]['method'], key
      assert_equal(SAMPLE_PATHS[key] || template, seen[0]['path'], key)
      headers = seen[0]['headers']
      assert_equal "Bearer #{KEY}", headers['authorization'], key
      assert_equal 'application/json', headers['accept'], key
      assert_match(%r{\Astampmitra-ruby/#{Regexp.escape(StampMitra::VERSION)} \(Ruby }, headers['user-agent'], key)
      if KEYED_POSTS.include?(key)
        assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, headers['idempotency-key'], key)
      else
        refute headers.key?('idempotency-key'), key
      end
      assert_matches_fixture(key, result)
    end
  end

  # A typed model must round-trip the documented success body without losing a field.
  def assert_matches_fixture(key, result)
    verb, template = key.split(' ', 2)
    slug = "#{verb.downcase}-#{template.delete('{}').tr('/', '-').sub(/\A-/, '')}".downcase
    path = File.join(fixtures_dir, "#{slug}.success.json")
    return unless File.exist?(path)

    expected = JSON.parse(File.read(path, encoding: 'UTF-8')).dig('response', 'body')
    assert_equal expected, result.to_h, "#{key}: typed result lost or changed fields of #{File.basename(path)}"
  end

  def test_every_spec_operation_was_exercised_against_the_mock
    MockServer.reset
    OPS.each_value { |call| call.call(client, nil) }
    hit = MockServer.recorded.map { |r| "#{r['method']} #{r['path']}" }
    assert_equal 62, hit.uniq.size
  end

  # ---- documented error fixtures: every operation x every documented status ---

  def test_every_documented_error_fixture_maps_to_the_right_exception
    classes = { 400 => StampMitra::ValidationError, 401 => StampMitra::AuthenticationError, 402 => StampMitra::PaymentRequiredError,
                403 => StampMitra::PermissionDeniedError, 404 => StampMitra::NotFoundError, 409 => StampMitra::ConflictError,
                422 => StampMitra::ValidationError, 429 => StampMitra::RateLimitError }
    checked = 0
    fixture_files.each do |name, fx|
      next unless fx['scenario'].to_s.start_with?('error-')

      status = fx.dig('response', 'status')
      call = OPS.fetch("#{fx.dig('operation', 'method')} #{fx.dig('operation', 'path')}")
      error = assert_raises(StampMitra::Error, name) { call.call(client(max_retries: 0), scenario(fx['scenario'])) }
      assert_equal(classes[status] || StampMitra::UpstreamError, error.class, name)
      assert_equal status, error.status, name
      body = fx.dig('response', 'body', 'error')
      assert_equal body['code'], error.code, name
      assert_equal body['message'], error.message, name
      assert_equal body['requestId'], error.request_id, name
      body['field'].nil? ? assert_nil(error.field, name) : assert_equal(body['field'], error.field, name)
      refute_includes error.message, KEY
      wallet = body.dig('details', 'wallet')
      wallet.nil? ? assert_nil(error.wallet, name) : assert_equal(wallet, error.wallet, name)
      assert_equal Array(body.dig('details', 'errors')).map { |i| i['code'] }, error.errors.map(&:code), name
      checked += 1
    end
    assert_operator checked, :>=, 300
  end

  def test_all_eleven_error_statuses_on_a_generic_route
    {
      400 => StampMitra::ValidationError, 401 => StampMitra::AuthenticationError, 402 => StampMitra::PaymentRequiredError,
      403 => StampMitra::PermissionDeniedError, 404 => StampMitra::NotFoundError, 409 => StampMitra::ConflictError,
      429 => StampMitra::RateLimitError, 500 => StampMitra::UpstreamError, 502 => StampMitra::UpstreamError,
      503 => StampMitra::UpstreamError, 504 => StampMitra::UpstreamError
    }.each do |status, klass|
      error = assert_raises(klass, status.to_s) { client(max_retries: 0).usage.summary(options: scenario("error-#{status}")) }
      assert_equal status, error.status
      refute_nil error.code
      refute_empty error.request_id.to_s
    end
  end

  def test_rate_limit_with_a_retry_after_header
    error = assert_raises(StampMitra::RateLimitError) { client(max_retries: 0).usage.summary(options: scenario('retry-after:7')) }
    assert_in_delta 7.0, error.retry_after
  end

  def test_retry_after_overrides_backoff
    assert_raises(StampMitra::RateLimitError) { client(max_retries: 1).usage.summary(options: scenario('retry-after:3')) }
    assert_equal [3.0], @sleeps
    assert_equal 2, MockServer.recorded.size
  end

  # Contract 1.2.0 sends Retry-After on every documented 429, so the delay is the header's value, not computed backoff.
  # (Jittered backoff for a 429 without the header is covered by the shared scenario get-429-no-retry-after-header.)
  def test_a_documented_429_carries_retry_after_which_replaces_the_computed_backoff
    error = assert_raises(StampMitra::RateLimitError) { client(max_retries: 1).estamp.list_states(options: scenario('error-429')) }
    assert_in_delta 1.0, error.retry_after
    assert_equal [1.0], @sleeps
  end

  # ---- every golden fixture of the 31 new operations, replayed through the SDK ------------------------------------------

  NEW_OPERATIONS = [
    'GET /v1/estamp/states/availability',
    'GET /v1/estamp/states/{stateCode}',
    'GET /v1/estamp/states/{stateCode}/requirements',
    'GET /v1/estamp/states/{stateCode}/districts',
    'GET /v1/estamp/states/{stateCode}/districts/{districtCode}/sros',
    'POST /v1/estamp/orders/validate',
    'POST /v1/estamp/orders',
    'GET /v1/estamp/orders',
    'GET /v1/estamp/orders/{id}',
    'POST /v1/estamp/orders/{id}/cancel',
    'GET /v1/estamp/orders/{id}/export',
    'GET /v1/estamp/orders/{id}/stamps',
    'POST /v1/estamp/orders/{orderId}/documents',
    'GET /v1/estamp/stamps/{stampId}',
    'POST /v1/estamp/stamps/{stampId}/cancel',
    'POST /v1/estamp/stamps/{stampId}/replace',
    'POST /v1/estamp/stamps/{stampId}/pan-card',
    'GET /v1/estamp/stamps/{stampId}/certificate',
    'GET /v1/estamp/wallet',
    'GET /v1/stamp-duty-wallet',
    'POST /v1/stamp-duty-wallet/topup',
    'GET /v1/stamp-duty-wallet/transactions',
    'GET /v1/stamp-duty-wallet/invoices',
    'GET /v1/stamp-duty-wallet/invoices/{id}',
    'GET /v1/service-fee-wallet',
    'POST /v1/service-fee-wallet/topup',
    'GET /v1/service-fee-wallet/transactions',
    'GET /v1/service-fee-wallet/invoices',
    'GET /v1/service-fee-wallet/invoices/{id}',
    'GET /v1/account/balance',
    'GET /v1/account/usage'
  ].freeze

  def test_the_table_covers_exactly_the_31_new_operations
    assert_equal 31, NEW_OPERATIONS.size
  end

  def replay_fixture(fixture)
    MockServer.reset
    op = "#{fixture.dig('operation', 'method')} #{fixture.dig('operation', 'path')}"
    request = fixture['request']
    options = { headers: { 'x-mock-scenario' => fixture['scenario'] } }
    sent_key = request.dig('headers', 'Idempotency-Key')
    options[:idempotency_key] = sent_key if sent_key
    result = error = nil
    begin
      result = OPS.fetch(op).call(client(max_retries: 0), options)
    rescue StampMitra::Error => e
      error = e
    end
    [op, request, result, error, MockServer.recorded.last]
  end

  def test_every_fixture_of_the_new_operations_replays_request_and_response
    count = 0
    fixture_files.each do |name, fx|
      op = "#{fx.dig('operation', 'method')} #{fx.dig('operation', 'path')}"
      next unless NEW_OPERATIONS.include?(op)

      op, request, result, error, seen = replay_fixture(fx)
      status = fx.dig('response', 'status')
      assert_equal request['method'], seen['method'], name
      assert_equal request['path'], seen['path'], name
      assert_equal request['query'], seen['query'], name if request['method'] == 'GET' && request['query']
      assert_request_body(name, request, seen)
      status < 400 ? assert_response(name, fx, result, error) : assert_error(name, fx, error)
      refute_nil seen['headers']['authorization'], op
      count += 1
    end
    assert_equal fixture_files.count { |_n, fx| NEW_OPERATIONS.include?("#{fx.dig('operation', 'method')} #{fx.dig('operation', 'path')}") }, count
    assert_operator count, :>=, 190
  end

  def assert_request_body(name, request, seen)
    if request['multipart']
      assert_match %r{\Amultipart/form-data; boundary=}, seen['headers']['content-type'], name
      parts = seen['body']['multipart']
      expected = request['multipart']['parts']
      assert_equal expected.map { |p| p['name'] }, parts.map { |p| p['name'] }, name
      expected.zip(parts).each do |want, got|
        %w[filename contentType value].each do |key|
          want[key].nil? ? assert_nil(got[key], name) : assert_equal(want[key], got[key], "#{name} #{key}")
        end
        assert_equal want['content'].bytesize, got['size'], name if want['content']
      end
    elsif request['body'].is_a?(Hash) && !request['body'].empty? && request['method'] == 'POST'
      assert_equal request['body'], seen['body'], name
    end
  end

  def assert_response(name, fixture, result, error)
    assert_nil error, "#{name}: #{error&.message}"
    expected = fixture.dig('response', 'body')
    assert_equal expected, result.to_h, name
    assert_equal fixture.dig('response', 'status'), result.response.status, name
  end

  def assert_error(name, fixture, error)
    refute_nil error, name
    assert_equal fixture.dig('response', 'status'), error.status, name
    assert_equal fixture.dig('response', 'body', 'error', 'code'), error.code, name
  end

  def test_the_create_order_key_is_generated_when_omitted_and_the_caller_key_wins
    client.estamp.orders.create(**ConformanceTest.order_args)
    key = MockServer.recorded.last['headers']['idempotency-key']
    assert_match(/\A[0-9a-f-]{36}\z/, key)
    MockServer.reset
    client.estamp.orders.create(**ConformanceTest.order_args, options: { idempotency_key: 'lease-2026-0412-v1' })
    assert_equal 'lease-2026-0412-v1', MockServer.recorded.last['headers']['idempotency-key']
  end

  def test_multipart_upload_is_a_real_multipart_request_with_file_and_type_parts
    client.estamp.orders.upload_document('estord_9c1f2a3b', file: StringIO.new(ConformanceTest.pdf), filename: 'pan.pdf', type: 'pan_card')
    seen = MockServer.recorded.last
    parts = seen['body']['multipart']
    assert_equal %w[file type], parts.map { |p| p['name'] }
    assert_equal 'pan.pdf', parts[0]['filename']
    assert_equal 'application/pdf', parts[0]['contentType']
    assert_equal ConformanceTest.pdf.bytesize, parts[0]['size']
    assert_equal 'pan_card', parts[1]['value']
    refute_empty seen['headers']['idempotency-key']
  end

  def test_the_new_never_retry_operations_make_exactly_one_attempt_against_the_mock
    {
      'POST /v1/estamp/orders/{id}/cancel' => 503, 'POST /v1/estamp/stamps/{stampId}/cancel' => 502,
      'POST /v1/estamp/stamps/{stampId}/replace' => 503, 'POST /v1/estamp/stamps/{stampId}/pan-card' => 503,
      'POST /v1/stamp-duty-wallet/topup' => 503, 'POST /v1/service-fee-wallet/topup' => 429
    }.each do |op, status|
      MockServer.reset
      assert_raises(StampMitra::Error, op) { OPS.fetch(op).call(client, headers: { 'x-mock-scenario' => "seq:nr#{status}#{op.hash.abs}:#{status},200" }) }
      assert_equal 1, MockServer.recorded.size, op
    end
  end

  def test_retry_after_is_honoured_on_503_and_on_a_keyed_429_for_the_new_routes
    client.estamp.get_state('MH', options: scenario('seq:ra503:503,200'))
    assert_equal 2, MockServer.recorded.size
    MockServer.reset
    @sleeps.clear
    client.estamp.orders.create(**ConformanceTest.order_args, options: scenario('seq:ra429:429,201'))
    assert_equal 2, MockServer.recorded.size
    keys = MockServer.recorded.map { |r| r['headers']['idempotency-key'] }
    assert_equal 1, keys.uniq.size
  end

  # ---- shared retry scenarios: once against the mock, once against a scripted loopback server ----

  scenarios = TestHelper.json('retry-scenarios.json')['scenarios']
  scenarios.each do |spec_case|
    next if spec_case['optional']

    name = spec_case['name'].tr('-', '_')
    # The mock's documented 409 for POST /v1/orders is IDEMPOTENCY_IN_PROGRESS, which the SDK retries by design (after Retry-After);
    # the "409 with any other code is not retried" rule is checked by the unit and loopback variants.
    unless spec_case['name'] == 'post-orders-409-not-retried' || spec_case['sequence'].any? { |s| s == 'timeout' || (s.is_a?(Hash) && (s['headers'] || s['body'])) }
      define_method("test_retry_scenario_on_mock_#{name}") { run_on_mock(spec_case) }
    end
    define_method("test_retry_scenario_on_loopback_#{name}") { run_on_loopback(spec_case) }
  end

  def scenario_client(spec_case, base_url, **extra)
    StampMitra::Client.new(api_key: KEY, base_url: base_url, max_retries: spec_case['maxRetries'] || 2, sleeper: ->(s) { @sleeps << s }, **extra)
  end

  def scenario_options(spec_case, extra = {})
    options = extra.dup
    options[:idempotency_key] = 'caller-key-1' if spec_case['idempotencyKey'] == true
    options
  end

  def judge(spec_case, client, options)
    result = error = nil
    begin
      result = perform(client, spec_case, options)
    rescue StampMitra::Error => e
      error = e
    end
    check_outcome(spec_case['outcome'], result, error)
  end

  def run_on_mock(spec_case)
    items = spec_case['sequence'].map do |s|
      if s == 'connection_error'
        'conn'
      else
        (s.is_a?(Hash) ? s['status'] : s).to_s
      end
    end
    options = scenario_options(spec_case, headers: { 'x-mock-scenario' => "seq:k#{SecureRandom.hex(4)}:#{items.join(',')}" })
    judge(spec_case, scenario_client(spec_case, @url), options)
    mine = MockServer.recorded.select { |r| r['path'] == spec_case['path'] }
    assert_equal spec_case['expectedAttempts'], mine.size, spec_case['name']
    check_keys(spec_case, mine.map { |r| r['headers']['idempotency-key'] })
  end

  def run_on_loopback(spec_case)
    steps = spec_case['sequence'].map do |item|
      case item
      when 'connection_error' then :drop
      when 'timeout' then :hang
      when Integer then { status: item, body: item >= 400 ? { 'error' => { 'code' => 'E', 'message' => 'm', 'requestId' => 'r' } } : { 'ok' => 1 } }
      else { status: item['status'], headers: item['headers'] || {}, body: item['body'] || { 'ok' => 1 } }
      end
    end
    ScriptedServer.run(*steps) do |server|
      judge(spec_case, scenario_client(spec_case, server.url, timeout: 0.4), scenario_options(spec_case))
      sleep 0.05
      assert_equal spec_case['expectedAttempts'], server.requests.size, spec_case['name']
      check_keys(spec_case, server.requests.map { |r| r.headers['idempotency-key'] })
      assert_in_delta spec_case['expectedDelayBeforeAttempt2Seconds'], @sleeps.first, 0.001 if spec_case['expectedDelayBeforeAttempt2Seconds']
    end
  end

  def test_idempotency_key_is_reused_across_retries_via_resource_methods
    client.verify.pan(pan: 'ABCDE1234F', options: scenario('seq:idem:503,502,200'))
    keys = MockServer.recorded.map { |r| r['headers']['idempotency-key'] }
    assert_equal 3, keys.size
    assert_equal 1, keys.uniq.size
    refute_nil keys.first

    MockServer.reset
    client.orders.create(external_order_id: 'o', external_customer_id: 'c', service_code: 's',
                         options: { idempotency_key: 'mine-1', headers: { 'x-mock-scenario' => 'seq:idem2:503,200' } })
    assert_equal %w[mine-1 mine-1], MockServer.recorded.map { |r| r['headers']['idempotency-key'] }
  end

  def test_retry_exhaustion_raises_the_last_error_after_max_retries_plus_one_attempts
    error = assert_raises(StampMitra::UpstreamError) { client.usage.summary(options: scenario('seq:ex:503,503,503,200')) }
    assert_equal 503, error.status
    assert_equal 3, MockServer.recorded.size
  end

  def test_no_retry_on_4xx
    assert_raises(StampMitra::NotFoundError) { client.orders.get('missing', options: scenario('seq:nf:404,200')) }
    assert_equal 1, MockServer.recorded.size
  end

  # ---- transport failures ----------------------------------------------------

  def test_timeout_against_a_slow_mock_response
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(StampMitra::TimeoutError) { client(max_retries: 0, timeout: 30).usage.summary(options: { timeout: 0.3, headers: { 'x-mock-scenario' => 'delay:1500' } }) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.2, 'per-call timeout must override the 30s default'
  end

  def test_timeouts_are_retried_for_get_then_raise
    assert_raises(StampMitra::TimeoutError) do
      client(max_retries: 1).usage.summary(options: { timeout: 0.2, headers: { 'x-mock-scenario' => 'delay:1000' } })
    end
    assert_operator MockServer.recorded.size, :>=, 2
  end

  def test_connection_refused
    port = TCPServer.open('127.0.0.1', 0) { |s| s.addr[1] }
    error = assert_raises(StampMitra::ConnectionError) do
      StampMitra::Client.new(api_key: KEY, base_url: "http://127.0.0.1:#{port}", max_retries: 1, sleeper: ->(s) { @sleeps << s }).usage.summary
    end
    refute_kind_of StampMitra::TimeoutError, error
    assert_equal 1, @sleeps.size
    refute_includes error.message, KEY
  end

  def test_connection_dropped_mid_request_is_retried_for_get_and_not_replayed_by_net_http
    client.usage.summary(options: scenario('seq:drop:conn,200'))
    assert_equal 2, MockServer.recorded.size
    MockServer.reset
    assert_raises(StampMitra::ConnectionError) { client(max_retries: 0).usage.summary(options: scenario('seq:drop2:conn,200')) }
    sleep 0.1
    assert_equal 1, MockServer.recorded.size, 'Net::HTTP replayed a dropped GET'
  end

  # ---- bodies the mock cannot produce (real loopback sockets) -----------------

  def page(ids, next_cursor)
    { status: 200, body: { 'items' => ids.map { |id| { 'id' => id, 'createdAt' => '2026-10-15T09:41:07.000Z', 'actorType' => 'api_key', 'service' => 'pan.verify' } },
                           'nextCursor' => next_cursor } }
  end

  def test_three_page_logs_pagination_over_real_sockets
    ScriptedServer.run(page(%w[a], 'c1'), page(%w[b], 'c2'), page(%w[c], nil)) do |server|
      ids = scenario_client({}, server.url).logs.each(limit: 1).map(&:id)
      assert_equal %w[a b c], ids
      assert_equal 3, server.requests.size
      assert_equal [nil, 'c1', 'c2'], server.requests.map { |r| URI.decode_www_form(URI("http://x#{r.path}").query.to_s).to_h['cursor'] }
      assert_equal 3, server.connections
    end
  end

  def test_logs_pagination_against_the_mock_stops_when_next_cursor_is_null
    ids = client.logs.each(limit: 50).map(&:id)
    refute_empty ids
    assert_equal 1, MockServer.recorded.size
  end

  def test_non_json_error_bodies_map_by_status
    [[502, StampMitra::UpstreamError], [429, StampMitra::RateLimitError], [404, StampMitra::NotFoundError]].each do |status, klass|
      ScriptedServer.run({ status: status, headers: { 'Content-Type' => 'text/html' }, body: '<html>Bad Gateway</html>' }) do |server|
        error = assert_raises(klass) { scenario_client({ 'maxRetries' => 0 }, server.url).usage.summary }
        assert_equal status, error.status
      end
    end
  end

  def test_unknown_response_fields_are_preserved
    body = { 'referenceId' => 'SMV-1', 'valid' => true, 'brandNewField' => { 'x' => 1 }, 'registeredName' => 'ACME' }
    ScriptedServer.run({ status: 200, body: body }) do |server|
      result = scenario_client({}, server.url).verify.pan(pan: 'ABCDE1234F')
      assert_equal({ 'x' => 1 }, result[:brandNewField])
      assert_equal body, result.to_h
    end
  end

  # ---- shared vectors -----------------------------------------------------------

  def test_webhook_vectors
    file = TestHelper.json('webhook-signatures.json')
    assert_equal 24, file['vectors'].size
    file['vectors'].each do |v|
      reason = StampMitra::Webhook.failure_reason(payload: v['payload'], timestamp: v['timestamp'], signature: v['signature'],
                                                  secret: v['secret'], tolerance: file['toleranceSeconds'], now: file['now'])
      v['expected']['valid'] ? assert_nil(reason, v['name']) : assert_equal(v['expected']['reason'], reason, v['name'])
    end
  end

  def test_validator_vectors
    methods = { 'vehicleNumber' => :vehicle_number, 'bankAccount' => :bank_account, 'passport' => :passport_file_number,
                'drivingLicense' => :driving_license, 'voterId' => :voter_id }
    count = 0
    TestHelper.json('validators.json')['validators'].each do |name, definition|
      method = methods.fetch(name, name.to_sym)
      definition['valid'].each { |input| StampMitra::Validators.public_send(method, input) && count += 1 }
      definition['invalid'].each do |input|
        assert_raises(StampMitra::ValidationError, "#{name} #{input.inspect}") { StampMitra::Validators.public_send(method, input) }
        count += 1
      end
    end
    assert_operator count, :>=, 100
  end
end
