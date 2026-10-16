# frozen_string_literal: true

require 'test_helper'

class WebhookTest < Minitest::Test
  W = StampMitra::Webhook
  FILE = TestHelper.json('webhook-signatures.json')
  NOW = FILE['now']

  FILE['vectors'].each do |vector|
    define_method("test_vector_#{vector['name'].tr('-', '_')}") do
      reason = W.failure_reason(payload: vector['payload'], timestamp: vector['timestamp'], signature: vector['signature'],
                                secret: vector['secret'], tolerance: FILE['toleranceSeconds'], now: NOW)
      if vector['expected']['valid']
        assert_nil reason
        assert W.verify_signature(payload: vector['payload'], timestamp: vector['timestamp'], signature: vector['signature'],
                                  secret: vector['secret'], now: NOW)
      else
        assert_equal vector['expected']['reason'], reason
        refute W.verify_signature(payload: vector['payload'], timestamp: vector['timestamp'], signature: vector['signature'],
                                  secret: vector['secret'], now: NOW)
      end
    end
  end

  Dir[File.join(TestHelper::FIXTURES, 'webhooks', '*.json')].each do |path|
    fx = JSON.parse(File.read(path, encoding: 'UTF-8'))
    define_method("test_spec_fixture_#{File.basename(path, '.json')}") do
      headers = fx['headers']
      event = W.construct_event_from_headers(payload: fx['rawBody'], headers: headers, secret: fx['secret'], now: fx['now'])
      assert_equal fx['event'], event.type
      assert_equal 'core_order_9f3a1c2b8e4d4a5f', event.core_order_id
      assert_equal headers['X-Webhook-Event-Id'], event.event_id
      assert_equal JSON.parse(fx['rawBody']), event.to_h
      assert_instance_of W::EVENT_CLASSES.fetch(event.core_event_type), event
    end
  end

  def test_all_eight_event_types_have_a_typed_class
    assert_equal 8, W::EVENT_CLASSES.size
    assert_equal W::EVENT_TYPES.sort, W::EVENT_CLASSES.values.map(&:new).map(&:type).sort
    assert_equal 8, W::EVENT_CLASSES.values.uniq.size
  end

  def secret
    'whsec_test_0123456789abcdef'
  end

  def signed(payload, timestamp: NOW - 5)
    [payload, timestamp.to_s, W.sign(payload: payload, timestamp: timestamp, secret: secret)]
  end

  def test_sign_matches_the_documented_scheme
    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, '1760605190.{"a":1}')
    assert_equal expected, W.sign(payload: '{"a":1}', timestamp: 1_760_605_190, secret: secret)
  end

  def test_construct_event_keeps_unknown_fields_and_unrecognised_types
    payload = '{"coreOrderId":"c1","coreEventType":"BRAND_NEW","occurredAt":"2026-01-01T00:00:00Z","extra":{"a":1}}'
    body, ts, sig = signed(payload)
    event = W.construct_event(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW, event_id: 'evt_9')
    assert_instance_of W::Event, event
    assert_nil event.type
    assert_equal({ 'a' => 1 }, event[:extra])
    assert_equal 'evt_9', event.event_id
    assert_equal ['extra'], event.unknown_fields
  end

  def test_construct_event_rejects_bad_input_with_typed_codes
    payload = '{"coreEventType":"ORDER_CREATED"}'
    body, ts, sig = signed(payload)
    error = assert_raises(StampMitra::SignatureVerificationError) { W.construct_event(payload: "#{body} ", timestamp: ts, signature: sig, secret: secret, now: NOW) }
    assert_equal 'SIGNATURE_MISMATCH', error.code
    error = assert_raises(StampMitra::SignatureVerificationError) { W.construct_event(payload: body, timestamp: '1', signature: sig, secret: secret, now: NOW) }
    assert_equal 'TIMESTAMP_OUTSIDE_TOLERANCE', error.code
    error = assert_raises(StampMitra::SignatureVerificationError) { W.construct_event(payload: body, timestamp: 'x', signature: sig, secret: secret, now: NOW) }
    assert_equal 'INVALID_TIMESTAMP', error.code
    ['[1,2]', '"str"', 'not json', '3'].each do |bad|
      b, t, s = signed(bad)
      error = assert_raises(StampMitra::SignatureVerificationError, bad) { W.construct_event(payload: b, timestamp: t, signature: s, secret: secret, now: NOW) }
      assert_equal 'INVALID_PAYLOAD', error.code
    end
  end

  def test_empty_or_non_string_secret_is_rejected_and_never_echoed
    body, ts, sig = signed('{}')
    ['', nil, 123].each do |bad|
      error = assert_raises(StampMitra::SignatureVerificationError) { W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: bad, now: NOW) }
      assert_equal 'MISSING_SECRET', error.code
    end
    error = assert_raises(StampMitra::SignatureVerificationError) { W.construct_event(payload: body, timestamp: ts, signature: sig, secret: 'whsec_wrong', now: NOW) }
    refute_includes error.message, 'whsec_wrong'
    refute_includes error.inspect, 'whsec_wrong'
  end

  def test_payload_must_be_the_raw_string
    _, ts, sig = signed('{}')
    [{ 'a' => 1 }, nil, 5, StringIO.new('{}')].each do |bad|
      error = assert_raises(StampMitra::SignatureVerificationError) { W.verify_signature(payload: bad, timestamp: ts, signature: sig, secret: secret, now: NOW) }
      assert_equal 'INVALID_PAYLOAD', error.code
    end
  end

  def test_tolerance_is_configurable_and_symmetric
    body, ts, sig = signed('{}', timestamp: NOW - 400)
    refute W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW)
    assert W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW, tolerance: 400)
    body, ts, sig = signed('{}', timestamp: NOW + 301)
    refute W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW)
  end

  def test_now_accepts_time_and_defaults_to_the_clock
    body, ts, sig = signed('{}', timestamp: Time.now.to_i)
    assert W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret)
    assert W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: Time.at(ts.to_i))
  end

  def test_nil_and_non_string_signatures_do_not_verify
    body, ts, = signed('{}')
    [nil, '', 123, 'abc'].each { |bad| refute W.verify_signature(payload: body, timestamp: ts, signature: bad, secret: secret, now: NOW) }
  end

  def test_unicode_payload_is_signed_over_bytes
    body, ts, sig = signed('{"name":"रवि कुमार","note":"café ₹500 ✓"}')
    assert W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW)
    assert W.verify_signature(payload: body.b, timestamp: ts, signature: sig, secret: secret, now: NOW)
    assert W.verify_signature(payload: body.dup.force_encoding('ISO-8859-1'), timestamp: ts, signature: sig, secret: secret, now: NOW)
  end

  def test_header_lookup_supports_hashes_rack_env_and_rails_style_objects
    payload = '{"coreOrderId":"c1","coreEventType":"ORDER_CREATED","occurredAt":"2026-01-01T00:00:00Z"}'
    body, ts, sig = signed(payload)
    variants = {
      'canonical' => { 'X-Webhook-Signature' => sig, 'X-Webhook-Timestamp' => ts, 'X-Webhook-Event-Id' => 'e1' },
      'lowercase' => { 'x-webhook-signature' => sig, 'x-webhook-timestamp' => ts, 'x-webhook-event-id' => 'e1' },
      'mixed' => { 'X-WEBHOOK-Signature' => sig, 'x-Webhook-TIMESTAMP' => ts, 'X-webhook-event-ID' => 'e1' },
      'rack env' => { 'HTTP_X_WEBHOOK_SIGNATURE' => sig, 'HTTP_X_WEBHOOK_TIMESTAMP' => ts, 'HTTP_X_WEBHOOK_EVENT_ID' => 'e1', 'REQUEST_METHOD' => 'POST' },
      'arrays' => { 'x-webhook-signature' => [sig], 'x-webhook-timestamp' => [ts], 'x-webhook-event-id' => ['e1'] },
      'symbols' => { x_webhook_signature: sig }
    }
    variants.each do |name, headers|
      next if name == 'symbols'

      event = W.construct_event_from_headers(payload: body, headers: headers, secret: secret, now: NOW)
      assert_equal 'order.created', event.type, name
      assert_equal 'e1', event.event_id, name
    end
    rails_like = Class.new do
      def initialize(map) = @map = map
      def [](key) = @map[key]
    end.new('X-Webhook-Signature' => sig, 'X-Webhook-Timestamp' => ts)
    assert_equal 'order.created', W.construct_event_from_headers(payload: body, headers: rails_like, secret: secret, now: NOW).type
  end

  def test_missing_headers
    error = assert_raises(StampMitra::SignatureVerificationError) { W.construct_event_from_headers(payload: '{}', headers: {}, secret: secret) }
    assert_equal 'MISSING_HEADERS', error.code
    error = assert_raises(StampMitra::SignatureVerificationError) do
      W.construct_event_from_headers(payload: '{}', headers: { 'X-Webhook-Signature' => 'x' }, secret: secret)
    end
    assert_equal 'MISSING_HEADERS', error.code
  end

  def test_secure_compare_both_implementations
    assert W.secure_compare('abc', 'abc')
    refute W.secure_compare('abc', 'abd')
    refute W.secure_compare('abc', 'ab')
    refute W.secure_compare('', 'a')
    assert W.secure_compare('', '')
    assert W.secure_compare('é', 'é')
    assert W.xor_equal?('same'.b, 'same'.b)
    refute W.xor_equal?('same'.b, 'sane'.b)
    refute W.xor_equal?("\x00".b, "\x01".b)
  end

  def test_secure_compare_falls_back_when_openssl_lacks_the_fixed_length_helper
    skip 'openssl provides no fixed_length_secure_compare' unless OpenSSL.respond_to?(:fixed_length_secure_compare)
    singleton = OpenSSL.singleton_class
    singleton.send(:alias_method, :__saved_flsc, :fixed_length_secure_compare)
    singleton.send(:remove_method, :fixed_length_secure_compare)
    begin
      refute_respond_to OpenSSL, :fixed_length_secure_compare
      assert W.secure_compare('abcdef', 'abcdef')
      refute W.secure_compare('abcdef', 'abcdeg')
      body, ts, sig = signed('{}')
      assert W.verify_signature(payload: body, timestamp: ts, signature: sig, secret: secret, now: NOW)
    ensure
      singleton.send(:alias_method, :fixed_length_secure_compare, :__saved_flsc)
      singleton.send(:remove_method, :__saved_flsc)
    end
  end
end
