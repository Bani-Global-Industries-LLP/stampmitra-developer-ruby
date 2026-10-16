# frozen_string_literal: true

require 'test_helper'

class RequestTest < Minitest::Test
  PAN_OK = { 'referenceId' => 'SMV-1', 'pan' => 'ABCDE1234F', 'valid' => true }.freeze

  def test_get_has_no_body_or_idempotency_key
    adapter = FakeAdapter.new({ status: 200, body: { 'externalOrderId' => 'o1', 'status' => 'CREATED' } })
    fake_client(adapter).orders.get_status('o1')
    call = adapter.calls.first
    assert_equal :get, call[:method]
    assert_nil call[:body]
    assert_equal [nil], adapter.header_values('Idempotency-Key')
    assert_equal 'https://api-b2b.stampmitra.in/v1/orders/o1/status', call[:url]
  end

  def test_every_post_but_replay_gets_a_uuid_v4_idempotency_key
    adapter = FakeAdapter.new
    client = fake_client(adapter)
    client.verify.pan(pan: 'ABCDE1234F')
    client.orders.create(external_order_id: 'o', external_customer_id: 'c', service_code: 's')
    client.estamp.calculate_duty(state_code: 'MH', article_code: '5', stamp_duty_amount: 1000)
    client.estamp.add_parties('o1', party_name: 'B')
    client.payments.intents.create(external_order_id: 'o', amount_minor: 100, currency: 'INR', payment_connection_id: 'pc')
    keys = adapter.header_values('Idempotency-Key')
    assert_equal 5, keys.size
    keys.each { |key| assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, key) }
    assert_equal 5, keys.uniq.size
  end

  def test_replay_sends_no_key_unless_the_caller_supplies_one
    adapter = FakeAdapter.new
    client = fake_client(adapter)
    client.webhooks.events.replay('evt_1')
    client.webhooks.events.replay('evt_1', options: { idempotency_key: 'mine' })
    assert_equal [nil, 'mine'], adapter.header_values('Idempotency-Key')
    assert_equal '{}', adapter.calls.first[:body]
  end

  def test_per_request_options_override_client_defaults
    adapter = FakeAdapter.new
    client = fake_client(adapter, timeout: 30)
    client.usage.summary(options: { timeout: 5, headers: { 'X-Req' => '1' } })
    client.usage.summary
    assert_equal [5.0, 30.0], adapter.calls.map { |c| c[:timeout] }
    assert_equal ['1', nil], adapter.header_values('X-Req')
  end

  def test_invalid_request_options_are_rejected_locally
    client = fake_client(FakeAdapter.new)
    [{ timeout: -1 }, { timeout: 'x' }, { max_retries: -1 }, { max_retries: 'x' }, { idempotency_key: '' }, { idempotency_key: "a\nb" },
     { headers: 'x' }, { headers: { "bad\nname" => 'x' } }, { headers: { 'X' => "a\r\nb" } }, { bogus: 1 },
     { headers: { 'Authorization' => 'Bearer other' } }, { headers: { 'x-api-key' => 'other' } }, { headers: { 'Host' => 'evil.test' } }].each do |opts|
      assert_raises(StampMitra::ValidationError, opts.inspect) { client.usage.summary(options: opts) }
    end
    assert_raises(StampMitra::ValidationError) { client.usage.summary(options: 'x') }
  end

  def test_post_body_uses_camel_case_and_drops_nil_fields
    adapter = FakeAdapter.new
    fake_client(adapter).verify.bank_account(account_number: '000123456789', ifsc: 'icic0001234', phone: '9876543210')
    assert_equal({ 'accountNumber' => '000123456789', 'ifsc' => 'ICIC0001234', 'phone' => '9876543210' }, adapter.bodies.first)
  end

  def test_query_parameters_are_encoded_and_nil_ones_dropped
    adapter = FakeAdapter.new({ status: 200, body: { 'items' => [], 'nextCursor' => nil } })
    fake_client(adapter).logs.list(from: Time.utc(2026, 10, 1, 5, 30), service: 'pan.verify', status: :success, limit: 50)
    url = adapter.calls.first[:url]
    assert_equal '/v1/logs', URI(url).path
    assert_equal({ 'from' => '2026-10-01T05:30:00.000Z', 'service' => 'pan.verify', 'status' => 'success', 'limit' => '50' },
                 URI.decode_www_form(URI(url).query).to_h)
  end

  def test_path_ids_are_validated_and_encoded
    adapter = FakeAdapter.new
    client = fake_client(adapter)
    ['', ' ', '.', '..', 'a/b', 'a\\b', '../etc', nil, 12.5, ['x']].each do |bad|
      assert_raises(StampMitra::ValidationError, bad.inspect) { client.orders.get(bad) }
    end
    assert_empty adapter.calls
    client.orders.get('ord 1?x=1#y%2F')
    client.orders.get(:sym)
    client.orders.get(42)
    client.services.get('estamp.instrument.rent_agreement')
    paths = adapter.calls.map { |c| URI(c[:url]).path }
    assert_equal ['/v1/orders/ord%201%3Fx%3D1%23y%252F', '/v1/orders/sym', '/v1/orders/42', '/v1/services/estamp.instrument.rent_agreement'], paths
    assert_nil URI(adapter.calls.first[:url]).query
  end

  def test_path_id_error_messages_name_the_parameter
    client = fake_client(FakeAdapter.new)
    {
      '' => 'id must not be empty', '..' => 'id must not be a dot segment', 'a/b' => 'id must not contain slashes', 5.5 => 'id must be a String'
    }.each do |bad, message|
      error = assert_raises(StampMitra::ValidationError) { client.orders.get(bad) }
      assert_equal message, error.message
      assert_equal 'id', error.field
    end
    error = assert_raises(StampMitra::ValidationError) { client.orders.create(external_order_id: '', external_customer_id: 'c', service_code: 's') }
    assert_equal 'externalOrderId is required', error.message
    error = assert_raises(StampMitra::ValidationError) { client.services.get(' ') }
    assert_equal 'service_code must not be empty', error.message
  end

  def test_non_ascii_ids_are_percent_encoded_as_utf8
    adapter = FakeAdapter.new
    fake_client(adapter).orders.get('ord-é')
    assert_equal '/v1/orders/ord-%C3%A9', URI(adapter.calls.first[:url]).path
  end

  def test_two_xx_statuses_are_success_and_exposed_through_with_response
    adapter = FakeAdapter.new({ status: 201, body: { 'externalOrderId' => 'o1', 'createdAt' => '2026-01-01T00:00:00Z' }, headers: { 'x-request-id' => 'rid-1' } })
    data, response = fake_client(adapter).with_response.orders.create(external_order_id: 'o1', external_customer_id: 'c', service_code: 's')
    assert_equal 'o1', data.external_order_id
    assert_equal 201, response.status
    assert_predicate response, :success?
    assert_equal 'rid-1', response.request_id
    assert_equal 1, response.attempts
    assert_includes response.body, 'externalOrderId'
    assert_equal 'application/json', response.headers['content-type']
    assert_equal 'rid-1', data.response.request_id
  end

  def test_with_response_returns_a_result_with_status_and_headers
    adapter = FakeAdapter.new({ status: 200, body: PAN_OK })
    result = fake_client(adapter).with_response.verify.pan(pan: 'ABCDE1234F')
    assert_instance_of StampMitra::Result, result
    assert_equal 200, result.status
    assert_kind_of Hash, result.headers
    assert_predicate result.data, :valid?
    assert_includes result.inspect, 'StampMitra::Result'
  end

  def test_plain_calls_return_the_model_directly
    result = fake_client(FakeAdapter.new({ status: 200, body: PAN_OK })).verify.pan(pan: 'ABCDE1234F')
    assert_instance_of StampMitra::Models::PanVerification, result
    assert_equal 200, result.response.status
  end

  def test_empty_success_body_is_an_empty_model
    result = fake_client(FakeAdapter.new({ status: 200, body: '' })).usage.summary
    assert_equal({}, result.to_h)
  end

  def test_success_with_a_non_json_body_raises_invalid_response
    error = assert_raises(StampMitra::Error) { fake_client(FakeAdapter.new({ status: 200, body: '<html>oops</html>' })).usage.summary }
    assert_equal 'INVALID_RESPONSE', error.code
    assert_equal 200, error.status
    assert_equal '<html>oops</html>', error.body
  end

  def test_an_unexpected_response_shape_raises_a_typed_error_not_an_argument_error
    [[1, 2], 'text', 5].each do |body|
      error = assert_raises(StampMitra::Error) { fake_client(FakeAdapter.new({ status: 200, body: JSON.generate(body) })).usage.summary }
      assert_equal 'INVALID_RESPONSE', error.code
      assert_equal 200, error.status
    end
    assert_equal({}, fake_client(FakeAdapter.new({ status: 200, body: 'null' })).usage.summary.to_h)
  end

  def test_services_list_is_a_bare_array_wrapped_in_a_service_list
    body = [{ 'serviceCode' => 'a', 'name' => 'A' }, { 'serviceCode' => 'b', 'name' => 'B', 'surprise' => 1 }]
    list = fake_client(FakeAdapter.new({ status: 200, body: body })).services.list
    assert_equal %w[a b], list.map(&:service_code)
    assert_equal 2, list.size
    assert_equal 'b', list[1].service_code
    assert_equal 1, list[1][:surprise]
    assert_equal body, list.to_h
    assert_equal 200, list.response.status
  end

  def test_generic_response_handles_hash_and_array_roots
    hash = fake_client(FakeAdapter.new({ status: 200, body: { 'states' => [{ 'code' => 'MH' }] } })).estamp.list_states
    assert_equal 'MH', hash['states'].first['code']
    assert_equal({ 'states' => [{ 'code' => 'MH' }] }, hash.to_h)
    array = fake_client(FakeAdapter.new({ status: 200, body: [{ 'code' => 'MH' }, { 'code' => 'DL' }] })).estamp.list_states
    assert_equal %w[MH DL], array.map { |s| s['code'] }
    assert_equal({ 'code' => 'DL' }, array[1])
    assert_equal({ 'items' => [{ 'code' => 'MH' }, { 'code' => 'DL' }] }, array.to_h)
  end
end
