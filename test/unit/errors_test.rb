# frozen_string_literal: true

require 'test_helper'

class ErrorsTest < Minitest::Test
  STATUS_CLASSES = {
    400 => StampMitra::ValidationError, 401 => StampMitra::AuthenticationError, 402 => StampMitra::PaymentRequiredError,
    403 => StampMitra::PermissionDeniedError, 404 => StampMitra::NotFoundError, 409 => StampMitra::ConflictError,
    429 => StampMitra::RateLimitError, 500 => StampMitra::UpstreamError, 502 => StampMitra::UpstreamError,
    503 => StampMitra::UpstreamError, 504 => StampMitra::UpstreamError
  }.freeze

  def error_body(code: 'SOME_CODE', message: 'Something', request_id: 'req-1', field: nil)
    { 'error' => { 'code' => code, 'message' => message, 'requestId' => request_id, 'field' => field }.compact }
  end

  def call_with(step, **client_options)
    fake_client(FakeAdapter.new(step), max_retries: 0, **client_options).usage.summary
  end

  def test_status_mapping_carries_code_message_request_id_and_body
    STATUS_CLASSES.each do |status, klass|
      error = assert_raises(klass, status.to_s) { call_with({ status: status, body: error_body(message: "msg #{status}") }) }
      assert_instance_of klass, error
      assert_equal status, error.status
      assert_equal 'SOME_CODE', error.code
      assert_equal "msg #{status}", error.message
      assert_equal 'req-1', error.request_id
      assert_equal error_body(message: "msg #{status}"), error.body
      assert_kind_of StampMitra::Error, error
    end
  end

  def test_validation_error_exposes_the_field
    error = assert_raises(StampMitra::ValidationError) { call_with({ status: 400, body: error_body(field: 'pan') }) }
    assert_equal 'pan', error.field
  end

  def test_forbidden_message_is_passed_through_verbatim
    message = 'Your API key is not IP-allowlisted for sensitive verification (driving licence / passport).'
    error = assert_raises(StampMitra::PermissionDeniedError) { call_with({ status: 403, body: error_body(message: message) }) }
    assert_equal message, error.message
  end

  def test_request_id_falls_back_to_the_response_header
    error = assert_raises(StampMitra::NotFoundError) do
      call_with({ status: 404, body: { 'error' => { 'code' => 'NOT_FOUND', 'message' => 'x' } }, headers: { 'x-request-id' => 'hdr-1' } })
    end
    assert_equal 'hdr-1', error.request_id
    assert_equal 'hdr-1', error.headers['x-request-id']
  end

  def test_non_json_error_bodies_still_map_by_status
    [[502, StampMitra::UpstreamError], [429, StampMitra::RateLimitError], [404, StampMitra::NotFoundError], [503, StampMitra::UpstreamError]].each do |status, klass|
      error = assert_raises(klass) { call_with({ status: status, body: '<html>Bad Gateway</html>', headers: { 'content-type' => 'text/html' } }) }
      assert_equal "HTTP #{status}", error.message
      assert_equal '<html>Bad Gateway</html>', error.body
      assert_nil error.code
    end
  end

  def test_empty_and_odd_json_error_bodies
    assert_nil assert_raises(StampMitra::UpstreamError) { call_with({ status: 500, body: '' }) }.body
    assert_equal [1, 2], assert_raises(StampMitra::UpstreamError) { call_with({ status: 500, body: '[1,2]' }) }.body
    error = assert_raises(StampMitra::NotFoundError) { call_with({ status: 404, body: { 'error' => 'plain string' } }) }
    assert_equal 'HTTP 404', error.message
    error = assert_raises(StampMitra::NotFoundError) { call_with({ status: 404, body: { 'error' => { 'message' => 5, 'code' => ['x'] } } }) }
    assert_equal 'HTTP 404', error.message
    assert_nil error.code
  end

  def test_unexpected_statuses_raise_the_base_error_and_redirects_are_not_followed
    [301, 302, 307, 418, 451].each do |status|
      adapter = FakeAdapter.new({ status: status, body: '', headers: { 'location' => 'https://evil.test/' } }, { status: 200, body: {} })
      error = assert_raises(StampMitra::Error) { fake_client(adapter, max_retries: 2).usage.summary }
      assert_instance_of StampMitra::Error, error
      assert_equal status, error.status
      assert_equal 1, adapter.calls.size, "status #{status} must not be retried or followed"
    end
  end

  def test_rate_limit_retry_after_seconds_and_http_date
    error = assert_raises(StampMitra::RateLimitError) { call_with({ status: 429, body: error_body, headers: { 'retry-after' => '7' } }) }
    assert_in_delta 7.0, error.retry_after
    error = assert_raises(StampMitra::RateLimitError) { call_with({ status: 429, body: error_body, headers: { 'retry-after' => '1.5' } }) }
    assert_in_delta 1.5, error.retry_after
    date = (Time.now + 30).httpdate
    error = assert_raises(StampMitra::RateLimitError) { call_with({ status: 429, body: error_body, headers: { 'retry-after' => date } }) }
    assert_in_delta 30.0, error.retry_after, 2.0
    error = assert_raises(StampMitra::RateLimitError) { call_with({ status: 429, body: error_body, headers: { 'retry-after' => 'soon' } }) }
    assert_nil error.retry_after
    error = assert_raises(StampMitra::RateLimitError) { call_with({ status: 429, body: error_body }) }
    assert_nil error.retry_after
  end

  def test_hierarchy
    assert_operator StampMitra::TimeoutError, :<, StampMitra::ConnectionError
    assert_operator StampMitra::ConnectionError, :<, StampMitra::Error
    assert_operator StampMitra::SignatureVerificationError, :<, StampMitra::Error
    assert_operator StampMitra::Error, :<, StandardError
    (STATUS_CLASSES.values - [StampMitra::TimeoutError]).each { |klass| assert_operator klass, :<, StampMitra::Error }
  end

  def test_local_validation_errors_have_no_status
    error = assert_raises(StampMitra::ValidationError) { fake_client(FakeAdapter.new).verify.pan(pan: 'x') }
    assert_nil error.status
    assert_equal 'pan', error.field
    assert_equal 'VALIDATION_ERROR', error.code
    assert_equal({}, error.headers)
  end

  def test_to_h_is_safe_to_log
    error = assert_raises(StampMitra::NotFoundError) { call_with({ status: 404, body: error_body }) }
    assert_equal({ class: 'StampMitra::NotFoundError', message: 'Something', status: 404, code: 'SOME_CODE', request_id: 'req-1', field: nil }, error.to_h)
  end

  def test_connection_errors_keep_the_original_failure_class_out_of_secrets
    error = assert_raises(StampMitra::ConnectionError) { fake_client(FakeAdapter.new(StampMitra::ConnectionError.new('boom')), max_retries: 0).usage.summary }
    assert_nil error.status
    assert_predicate error, :retryable?
  end
end
