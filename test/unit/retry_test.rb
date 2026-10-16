# frozen_string_literal: true

require 'test_helper'
require 'support/scenarios'

class RetryTest < Minitest::Test
  include Scenarios

  # Executes the shared retry-scenarios.json against a scripted in-memory adapter.
  scenarios = TestHelper.json('retry-scenarios.json')['scenarios']

  def self.step_for(item)
    case item
    when 'connection_error' then StampMitra::ConnectionError.new('connection reset')
    when 'timeout' then StampMitra::TimeoutError.new('timed out')
    when Integer then { status: item, body: item >= 400 ? { 'error' => { 'code' => 'E', 'message' => 'm', 'requestId' => 'r' } } : { 'ok' => true } }
    else { status: item['status'], headers: (item['headers'] || {}).transform_keys(&:downcase), body: item['body'] || { 'ok' => true } }
    end
  end

  scenarios.each do |scenario|
    next if scenario['optional']

    define_method("test_shared_scenario_#{scenario['name'].tr('-', '_')}") { run_scenario(scenario) }
  end

  def run_scenario(scenario)
    steps = scenario['sequence'].map { |item| self.class.step_for(item) }
    adapter = FakeAdapter.new(*steps)
    sleeps = []
    client = fake_client(adapter, sleeps: sleeps, max_retries: scenario['maxRetries'] || 2)
    options = scenario['idempotencyKey'] == true ? { idempotency_key: 'caller-key-1' } : nil
    outcome = scenario['outcome']
    result = nil
    error = nil
    begin
      result = perform(client, scenario, options)
    rescue StampMitra::Error => e
      error = e
    end
    check_outcome(outcome, result, error)
    assert_equal scenario['expectedAttempts'], adapter.calls.size, scenario['name']
    check_keys(scenario, adapter.header_values('Idempotency-Key'))
    return unless scenario['expectedDelayBeforeAttempt2Seconds']

    assert_in_delta scenario['expectedDelayBeforeAttempt2Seconds'], sleeps.first, 0.001
  end

  def test_verification_retries_reuse_the_generated_key
    adapter = FakeAdapter.new({ status: 503, body: {} }, { status: 502, body: {} }, { status: 200, body: { 'referenceId' => 'r', 'valid' => true } })
    result = fake_client(adapter).verify.pan(pan: 'ABCDE1234F')
    assert_predicate result, :valid?
    assert_equal 3, adapter.calls.size
    assert_equal 1, adapter.header_values('Idempotency-Key').uniq.size
    refute_nil adapter.header_values('Idempotency-Key').first
  end

  def test_retry_after_header_is_honoured_and_capped
    sleeps = []
    adapter = FakeAdapter.new({ status: 429, body: {}, headers: { 'retry-after' => '3' } }, { status: 503, body: {}, headers: { 'retry-after' => '3600' } }, { status: 200, body: {} })
    fake_client(adapter, sleeps: sleeps).usage.summary
    assert_equal [3.0, 60.0], sleeps
  end

  def test_backoff_is_full_jitter_within_exponential_ceilings
    sleeps = []
    adapter = FakeAdapter.new({ status: 503, body: {} })
    20.times do
      assert_raises(StampMitra::UpstreamError) { fake_client(adapter, sleeps: sleeps, max_retries: 6).usage.summary }
    end
    per_attempt = sleeps.each_slice(6).to_a
    ceilings = [0.5, 1.0, 2.0, 4.0, 8.0, 8.0]
    per_attempt.each { |slice| slice.each_with_index { |value, i| assert_operator value, :<=, ceilings[i]; assert_operator value, :>=, 0 } }
    assert_operator sleeps.uniq.size, :>, 20, 'jitter should randomise delays'
  end

  def test_max_retries_per_request_overrides_the_client_default
    adapter = FakeAdapter.new({ status: 503, body: {} })
    assert_raises(StampMitra::UpstreamError) { fake_client(adapter, max_retries: 5).usage.summary(options: { max_retries: 1 }) }
    assert_equal 2, adapter.calls.size
  end

  def test_post_without_a_key_is_never_retried_even_on_connection_errors
    adapter = FakeAdapter.new(StampMitra::ConnectionError.new('reset'), { status: 200, body: {} })
    assert_raises(StampMitra::ConnectionError) { fake_client(adapter).webhooks.events.replay('evt_1') }
    assert_equal 1, adapter.calls.size
  end

  def test_tls_failures_are_not_retried
    adapter = FakeAdapter.new(StampMitra::ConnectionError.new('TLS error', retryable: false), { status: 200, body: {} })
    assert_raises(StampMitra::ConnectionError) { fake_client(adapter).usage.summary }
    assert_equal 1, adapter.calls.size
  end

  def test_attempts_are_reported_on_the_response
    adapter = FakeAdapter.new({ status: 503, body: {} }, { status: 200, body: {} })
    _data, response = fake_client(adapter).with_response.usage.summary
    assert_equal 2, response.attempts
  end

  def test_no_secure_random_source_fails_with_a_clear_error
    SecureRandom.stub(:uuid, -> { raise NotImplementedError, 'no source' }) do
      error = assert_raises(StampMitra::Error) { fake_client(FakeAdapter.new).verify.pan(pan: 'ABCDE1234F') }
      assert_equal 'NO_SECURE_RANDOM', error.code
    end
  end
end
