# frozen_string_literal: true

require 'test_helper'
require 'support/mock_server'
require 'support/scenarios'
require 'support/spec_coverage'
require 'securerandom'

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
  }.freeze

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
    'POST /v1/webhooks/events/{id}/replay' => '/v1/webhooks/events/evt_1/replay'
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

  # ---- 31 operations ---------------------------------------------------------

  def test_there_are_exactly_31_operations_and_they_match_the_spec
    assert_equal 31, OPS.size
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
      if verb == 'POST' && !key.include?('/replay')
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
    assert_equal 31, hit.uniq.size
  end

  # ---- documented error fixtures: every operation x every documented status ---

  def test_every_documented_error_fixture_maps_to_the_right_exception
    classes = { 400 => StampMitra::ValidationError, 401 => StampMitra::AuthenticationError, 402 => StampMitra::PaymentRequiredError,
                403 => StampMitra::PermissionDeniedError, 404 => StampMitra::NotFoundError, 409 => StampMitra::ConflictError,
                429 => StampMitra::RateLimitError }
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
      checked += 1
    end
    assert_operator checked, :>=, 100
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

  def test_429_without_retry_after_uses_jittered_backoff
    error = assert_raises(StampMitra::RateLimitError) { client(max_retries: 1).estamp.list_states(options: scenario('error-429')) }
    assert_nil error.retry_after
    assert_equal 1, @sleeps.size
    assert_operator @sleeps.first, :<=, 0.5
  end

  # ---- shared retry scenarios: once against the mock, once against a scripted loopback server ----

  scenarios = TestHelper.json('retry-scenarios.json')['scenarios']
  scenarios.each do |spec_case|
    next if spec_case['optional']

    name = spec_case['name'].tr('-', '_')
    unless spec_case['sequence'].any? { |s| s == 'timeout' || (s.is_a?(Hash) && (s['headers'] || s['body'])) }
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
