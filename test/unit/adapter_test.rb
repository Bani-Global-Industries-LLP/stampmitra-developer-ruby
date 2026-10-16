# frozen_string_literal: true

require 'test_helper'

# Exercises the real Net::HTTP adapter against a scripted loopback server.
class AdapterTest < Minitest::Test
  def client_for(server, **options)
    StampMitra::Client.new(api_key: KEY, base_url: server.url, sleeper: ->(_) {}, **options)
  end

  def test_successful_round_trip_uses_a_fresh_connection_each_time
    ScriptedServer.run({ status: 200, body: { 'totalApiRequests' => 1 } }) do |server|
      client = client_for(server)
      2.times { assert_equal 1, client.usage.summary['totalApiRequests'] }
      assert_equal 2, server.connections
      assert_equal 'close', server.requests.first.headers['connection']
      assert_equal "Bearer #{KEY}", server.requests.first.headers['authorization']
      assert_equal 'GET', server.requests.first.verb
      assert_equal '/v1/usage/summary', server.requests.first.path
    end
  end

  def test_post_sends_a_json_body_with_content_length
    ScriptedServer.run({ status: 201, body: { 'externalOrderId' => 'o1', 'createdAt' => 'x' } }) do |server|
      client_for(server).orders.create(external_order_id: 'o1', external_customer_id: 'c1', service_code: 's', details: { 'k' => 'é₹' })
      request = server.requests.first
      assert_equal 'POST', request.verb
      assert_equal 'application/json', request.headers['content-type']
      assert_equal({ 'externalOrderId' => 'o1', 'externalCustomerId' => 'c1', 'serviceCode' => 's', 'details' => { 'k' => 'é₹' } }, JSON.parse(request.body))
      assert_equal request.body.bytesize, request.headers['content-length'].to_i
      assert_match(/\A[0-9a-f-]{36}\z/, request.headers['idempotency-key'])
    end
  end

  # Lesson from the Go SDK: Net::HTTP must never silently replay a request on a dropped connection.
  def test_a_dropped_connection_is_not_silently_replayed_by_net_http
    skip 'TruffleRuby Net::HTTP replays dropped GETs itself' if RUBY_ENGINE == 'truffleruby'

    ScriptedServer.run(:drop, { status: 200, body: {} }) do |server|
      client = client_for(server, max_retries: 0)
      assert_raises(StampMitra::ConnectionError) { client.usage.summary }
      sleep 0.05
      assert_equal 1, server.requests.size, 'Net::HTTP replayed the GET behind the SDK\'s back'
    end
  end

  def test_sdk_retries_after_a_drop_exactly_once_per_configured_retry
    ScriptedServer.run(:drop, :drop, { status: 200, body: { 'ok' => 1 } }) do |server|
      assert_equal 1, client_for(server, max_retries: 2).usage.summary['ok']
      assert_equal 3, server.requests.size
    end
    ScriptedServer.run(:drop, { status: 200, body: {} }) do |server|
      assert_raises(StampMitra::ConnectionError) { client_for(server, max_retries: 0).usage.summary }
      sleep 0.05
      assert_equal 1, server.requests.size
    end
  end

  def test_redirects_are_never_followed_and_credentials_do_not_leave_the_host
    ScriptedServer.run({ status: 302, headers: { 'Location' => 'http://127.0.0.1:1/steal' }, body: '' }, { status: 200, body: {} }) do |server|
      error = assert_raises(StampMitra::Error) { client_for(server).usage.summary }
      assert_equal 302, error.status
      assert_equal 1, server.requests.size
    end
  end

  def test_read_timeout_raises_timeout_error_and_is_retried_for_get
    ScriptedServer.run(:hang, { status: 200, body: { 'ok' => 1 } }) do |server|
      client = client_for(server, timeout: 0.3, max_retries: 1)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_equal 1, client.usage.summary['ok']
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
      assert_equal 2, server.requests.size
    end
    ScriptedServer.run(:hang) do |server|
      error = assert_raises(StampMitra::TimeoutError) { client_for(server, timeout: 0.2, max_retries: 0).usage.summary }
      assert_kind_of StampMitra::ConnectionError, error
      assert_match(/timed out after 0\.2s/, error.message)
      refute_includes error.message, KEY
    end
  end

  def test_per_request_timeout_overrides_the_client_timeout
    ScriptedServer.run(:hang) do |server|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(StampMitra::TimeoutError) { client_for(server, timeout: 30, max_retries: 0).usage.summary(options: { timeout: 0.2 }) }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
    end
  end

  def test_connection_refused
    port = TCPServer.open('127.0.0.1', 0) { |s| s.addr[1] }
    sleeps = []
    client = StampMitra::Client.new(api_key: KEY, base_url: "http://127.0.0.1:#{port}", max_retries: 1, sleeper: ->(s) { sleeps << s })
    error = assert_raises(StampMitra::ConnectionError) { client.usage.summary }
    refute_kind_of StampMitra::TimeoutError, error
    assert_equal 1, sleeps.size
    refute_includes error.message, KEY
  end

  def test_non_json_and_unknown_field_responses_over_a_real_socket
    ScriptedServer.run({ status: 502, headers: { 'Content-Type' => 'text/html' }, body: '<html>Bad Gateway</html>' }) do |server|
      error = assert_raises(StampMitra::UpstreamError) { client_for(server, max_retries: 0).usage.summary }
      assert_equal 502, error.status
      assert_equal '<html>Bad Gateway</html>', error.body
    end
    body = { 'referenceId' => 'SMV-1', 'valid' => true, 'brandNewField' => { 'x' => 1 }, 'registeredName' => 'ACME' }
    ScriptedServer.run({ status: 200, body: body }) do |server|
      result = client_for(server).verify.pan(pan: 'ABCDE1234F')
      assert_predicate result, :valid?
      assert_equal({ 'x' => 1 }, result[:brandNewField])
      assert_equal body, result.to_h
    end
  end

  def test_utf8_response_bodies_are_decoded_regardless_of_the_default_external_encoding
    ScriptedServer.run({ status: 200, body: { 'registeredName' => 'रवि कुमार', 'referenceId' => 'r', 'valid' => true } }) do |server|
      result = client_for(server).verify.pan(pan: 'ABCDE1234F')
      assert_equal 'रवि कुमार', result.registered_name
      assert_equal Encoding::UTF_8, result.registered_name.encoding
    end
  end

  def test_untrusted_tls_certificates_are_rejected_and_not_retried
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    context = OpenSSL::SSL::SSLContext.new
    context.cert = cert
    context.key = key
    ScriptedServer.run({ status: 200, body: {} }, ssl_context: context) do |server|
      client = StampMitra::Client.new(api_key: KEY, base_url: "https://127.0.0.1:#{server.port}", max_retries: 3, sleeper: ->(_) {})
      error = assert_raises(StampMitra::ConnectionError) { client.usage.summary }
      assert_match(/TLS error/, error.message)
      refute_predicate error, :retryable?
      sleep 0.05
      assert_empty server.requests
    end
  end

  def test_the_adapter_disables_net_http_internal_retries_and_verifies_tls
    http = StampMitra::NetHttpAdapter.new.send(:build_http, URI('https://api-b2b.stampmitra.in'), 30.0)
    assert_equal 0, http.max_retries
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal OpenSSL::SSL::TLS1_2_VERSION, http.min_version
    assert_in_delta 10.0, http.open_timeout
    assert_in_delta 30.0, http.read_timeout
  end

  def test_custom_adapters_can_be_injected
    adapter = ->(**) { { status: 200, headers: {}, body: '{"totalApiRequests":9}' } }
    client = StampMitra::Client.new(api_key: KEY, adapter: adapter)
    assert_equal 9, client.usage.summary['totalApiRequests']
  end
end
