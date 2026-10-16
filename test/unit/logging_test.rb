# frozen_string_literal: true

require 'test_helper'
require 'logger'
require 'stringio'

class LoggingTest < Minitest::Test
  PAN_RESULT = { 'referenceId' => 'SMV-1', 'pan' => 'ABCDE1234F', 'valid' => true, 'registeredName' => 'RAHUL KUMAR SHARMA',
                 'fatherName' => 'SURESH SHARMA', 'message' => 'PAN ABCDE1234F is Valid' }.freeze

  def logged(adapter_steps = [{ status: 200, body: PAN_RESULT }], level: Logger::DEBUG)
    io = StringIO.new
    logger = Logger.new(io, level: level)
    client = fake_client(FakeAdapter.new(*adapter_steps), logger: logger)
    yield client
    io.string
  end

  def test_nothing_is_logged_without_a_logger
    adapter = FakeAdapter.new
    out = StringIO.new
    original = $stdout
    $stdout = out
    fake_client(adapter).verify.pan(pan: 'ABCDE1234F')
    $stdout = original
    assert_empty out.string
  ensure
    $stdout = original
  end

  def test_api_key_and_pii_never_reach_the_log
    log = logged { |client| client.verify.pan(pan: 'ABCDE1234F', name: 'Rahul Kumar Sharma') }
    refute_includes log, KEY
    refute_includes log, 'abcdefgh12345678'
    refute_includes log, 'ABCDE1234F'
    refute_includes log, 'Rahul Kumar Sharma'
    refute_includes log, 'RAHUL KUMAR SHARMA'
    refute_includes log, 'SURESH'
    assert_includes log, '[REDACTED]'
    assert_includes log, '******234F'
    assert_includes log, 'SMV-1'
  end

  def test_authorization_header_is_redacted_and_other_headers_remain
    log = logged { |client| client.usage.summary(options: { headers: { 'X-Trace' => 'trace-1', 'X-Custom-Secret' => 'visible' } }) }
    assert_match(/"Authorization"=>"\[REDACTED\]"/, log)
    assert_includes log, 'trace-1'
    refute_includes log, 'Bearer'
  end

  def test_account_numbers_gstins_and_non_json_bodies_are_masked
    log = logged([{ status: 200, body: { 'referenceId' => 'r', 'valid' => true, 'nameAtBank' => 'A B', 'gstin' => '27ABCDE1234F1Z5' } }]) do |client|
      client.verify.bank_account(account_number: '000123456789', ifsc: 'ICIC0001234', name: 'Rahul', phone: '9876543210')
    end
    %w[000123456789 9876543210 Rahul 27ABCDE1234F1Z5 ICIC0001234].each { |secret| refute_includes log, secret }
    log = logged([{ status: 502, body: '<html>ABCDE1234F</html>' }]) { |client| assert_raises(StampMitra::UpstreamError) { client.usage.summary(options: { max_retries: 0 }) } }
    refute_includes log, 'ABCDE1234F'
    assert_includes log, 'non-JSON body'
  end

  def test_key_in_free_text_is_scrubbed
    assert_equal 'token [REDACTED] end', StampMitra::Redaction.scrub("token #{KEY} end")
    assert_equal 'live [REDACTED]', StampMitra::Redaction.scrub('live sk_live_ABCDEFGH_12-34')
    assert_equal 'see ******234F ok', StampMitra::Redaction.scrub('see ABCDE1234F ok')
  end

  def test_logger_above_debug_level_receives_nothing
    assert_empty logged(level: Logger::INFO) { |client| client.verify.pan(pan: 'ABCDE1234F') }
  end

  def test_retries_and_errors_are_logged_without_secrets
    log = logged([StampMitra::ConnectionError.new('reset'), { status: 200, body: PAN_RESULT }]) { |client| client.usage.summary }
    assert_includes log, 'attempt=1'
    assert_includes log, 'attempt=2'
    assert_includes log, 'transport error'
    refute_includes log, KEY
  end

  def test_redaction_mask_covers_nested_structures_and_normalised_keys
    masked = StampMitra::Redaction.mask('items' => [{ 'account_number' => '000123456789', 'Registered-Name' => 'X', 'keep' => 'ok', 'name' => nil }],
                                        'directors' => [{ 'din' => '01234567', 'name' => 'Asha' }])
    assert_equal '********6789', masked['items'][0]['account_number']
    assert_equal '[REDACTED]', masked['items'][0]['Registered-Name']
    assert_equal 'ok', masked['items'][0]['keep']
    assert_nil masked['items'][0]['name']
    assert_equal '****4567', masked['directors'][0]['din']
    assert_equal '[REDACTED]', masked['directors'][0]['name']
  end

  def test_redaction_headers_helper
    out = StampMitra::Redaction.headers('Authorization' => 'Bearer x', 'X-API-KEY' => 'k', 'Cookie' => 'c', 'Accept' => 'a', 'Multi' => %w[1 2])
    assert_equal({ 'Authorization' => '[REDACTED]', 'X-API-KEY' => '[REDACTED]', 'Cookie' => '[REDACTED]', 'Accept' => 'a', 'Multi' => '1, 2' }, out)
  end
end
