# frozen_string_literal: true

require 'test_helper'
require 'pp'
require 'yaml'
require 'stringio'

class ClientTest < Minitest::Test
  def with_env(value)
    old = ENV.fetch('STAMPMITRA_API_KEY', nil)
    value.nil? ? ENV.delete('STAMPMITRA_API_KEY') : ENV['STAMPMITRA_API_KEY'] = value
    yield
  ensure
    old.nil? ? ENV.delete('STAMPMITRA_API_KEY') : ENV['STAMPMITRA_API_KEY'] = old
  end

  def test_environment_is_detected_from_the_key
    assert_equal 'test', StampMitra::Client.new(api_key: 'sk_test_abcdefgh').environment
    assert_equal 'live', StampMitra::Client.new(api_key: 'sk_live_abcdefgh').environment
  end

  def test_key_is_read_from_the_environment
    with_env('sk_test_fromenv0001') { assert_equal 'test', StampMitra::Client.new.environment }
  end

  def test_missing_key_raises_authentication_error
    with_env(nil) do
      error = assert_raises(StampMitra::AuthenticationError) { StampMitra::Client.new }
      assert_equal 'MISSING_API_KEY', error.code
    end
    with_env('') { assert_raises(StampMitra::AuthenticationError) { StampMitra::Client.new(api_key: '  ') } }
  end

  def test_malformed_keys_are_rejected_unless_custom_keys_are_allowed
    ['sk_test_short', 'pk_test_abcdefgh', 'sk_prod_abcdefgh', "sk_test_abc\ndefgh", 'sk_test_abc defgh'].each do |bad|
      assert_raises(StampMitra::AuthenticationError, bad) { StampMitra::Client.new(api_key: bad) }
    end
    assert_equal 'custom', StampMitra::Client.new(api_key: 'whatever-key', allow_custom_key: true).environment
  end

  def test_surrounding_whitespace_in_the_key_is_trimmed
    adapter = FakeAdapter.new
    client = StampMitra::Client.new(api_key: "  #{KEY}\n", adapter: adapter)
    client.usage.summary
    assert_equal "Bearer #{KEY}", adapter.calls.last[:headers]['Authorization']
  end

  def test_custom_keys_with_header_injection_are_rejected
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: "abc\r\nX-Evil: 1", allow_custom_key: true) }
  end

  def test_base_url_rules
    ok = ['https://api-b2b.stampmitra.in', 'https://example.com/prefix/', 'http://localhost:4010', 'http://127.0.0.1:4010', 'http://[::1]:4010']
    ok.each { |url| refute_nil StampMitra::Client.new(api_key: KEY, base_url: url).base_url, url }
    bad = ['http://api-b2b.stampmitra.in', 'ftp://example.com', 'https://user:pass@example.com', 'https://example.com?x=1',
           'https://example.com#frag', 'not a url', '', 'https://', '//example.com', 'http://localhost.evil.com']
    bad.each { |url| assert_raises(StampMitra::ValidationError, url) { StampMitra::Client.new(api_key: KEY, base_url: url) } }
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, base_url: nil) }
  end

  def test_base_url_trailing_slash_is_normalised
    assert_equal 'https://example.com/prefix', StampMitra::Client.new(api_key: KEY, base_url: 'https://example.com/prefix/').base_url
  end

  def test_invalid_numeric_options
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, timeout: 0) }
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, timeout: 'x') }
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, max_retries: -1) }
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, max_retries: 1.5) }
  end

  def test_default_headers_cannot_override_credentials_or_framing
    %w[Authorization x-api-key Host Content-Length].each do |name|
      assert_raises(StampMitra::ValidationError, name) { StampMitra::Client.new(api_key: KEY, default_headers: { name => 'x' }) }
    end
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, default_headers: { 'X-A' => "a\r\nb" }) }
    assert_raises(StampMitra::ValidationError) { StampMitra::Client.new(api_key: KEY, default_headers: { 'X A' => 'a' }) }
  end

  def test_request_headers_user_agent_and_auth
    adapter = FakeAdapter.new({ status: 200, body: { 'referenceId' => 'r', 'valid' => true } })
    client = fake_client(adapter, app_info: { name: 'my-app', version: '1.2', url: 'https://x.test' }, default_headers: { 'X-Trace' => 't1' })
    client.verify.pan(pan: 'ABCDE1234F')
    headers = adapter.calls.first[:headers]
    assert_equal "Bearer #{KEY}", headers['Authorization']
    assert_equal 'application/json', headers['Accept']
    assert_equal 'application/json', headers['Content-Type']
    assert_equal 't1', headers['X-Trace']
    assert_match(%r{\Astampmitra-ruby/#{Regexp.escape(StampMitra::VERSION)} \(Ruby #{Regexp.escape(RUBY_VERSION)}\) my-app/1.2 \(https://x.test\)\z}, headers['User-Agent'])
  end

  def test_app_info_cannot_inject_headers
    adapter = FakeAdapter.new
    fake_client(adapter, app_info: { name: "evil\r\nX-Injected: 1" }).usage.summary
    refute_match(/[\r\n]/, adapter.calls.first[:headers]['User-Agent'])
  end

  # ---- the key must never leak ------------------------------------------------

  def dump_everything(client)
    [client.inspect, client.to_s, client.verify.inspect, client.payments.inspect, client.webhooks.inspect,
     client.with_response.inspect, PP.pp(client, +''), PP.pp(client.verify, +''), client.instance_variables.map { |v| client.instance_variable_get(v).inspect }.join,
     client.verify.instance_variables.map { |v| client.verify.instance_variable_get(v).inspect }.join,
     client.verify.send(:transport).inspect, PP.pp(client.verify.send(:transport), +'')].join("\n")
  end

  def test_key_is_not_in_inspect_to_s_or_pp_output
    client = StampMitra::Client.new(api_key: KEY)
    refute_includes dump_everything(client), KEY
    refute_includes dump_everything(client), 'abcdefgh12345678'
  end

  def test_key_is_not_reachable_through_yaml_json_or_marshal
    client = StampMitra::Client.new(api_key: KEY)
    transport = client.verify.send(:transport)
    secret = transport.instance_variable_get(:@api_key)
    refute_includes secret.to_yaml, KEY
    refute_includes secret.to_json, KEY
    refute_includes secret.to_s, KEY
    assert_raises(TypeError) { Marshal.dump(secret) }
    assert_raises(TypeError) { Marshal.dump(client) }
  end

  def test_key_is_not_in_error_messages
    adapter = FakeAdapter.new({ status: 401, body: { 'error' => { 'code' => 'UNAUTHORIZED', 'message' => "bad key #{KEY}", 'requestId' => 'r1' } } })
    error = assert_raises(StampMitra::AuthenticationError) { fake_client(adapter).usage.summary }
    refute_includes error.message, KEY
    refute_includes error.inspect, KEY
    refute_includes error.to_h.to_s, KEY
  end

  def test_validate_input_can_be_disabled
    adapter = FakeAdapter.new
    fake_client(adapter, validate_input: false).verify.pan(pan: 'not-a-pan')
    assert_equal 'not-a-pan', adapter.bodies.first['pan']
    assert_raises(StampMitra::ValidationError) { fake_client(FakeAdapter.new).verify.pan(pan: 'not-a-pan') }
  end

  def test_validation_failure_sends_nothing
    adapter = FakeAdapter.new
    assert_raises(StampMitra::ValidationError) { fake_client(adapter).verify.pan(pan: 'bad') }
    assert_empty adapter.calls
  end

  def test_resources_are_exposed
    client = StampMitra::Client.new(api_key: KEY)
    %i[verify services estamp orders payments usage logs webhooks].each { |name| refute_nil client.public_send(name), name }
    refute_nil client.payments.intents
    refute_nil client.webhooks.events
  end
end
