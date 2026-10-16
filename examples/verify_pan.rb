# frozen_string_literal: true

# Verifies a PAN. Every call is billed, including valid: false results.
#
#   STAMPMITRA_API_KEY=sk_test_... ruby examples/verify_pan.rb ABCDE1234F "Rahul Kumar"
#
# Set STAMPMITRA_BASE_URL=http://127.0.0.1:4010 to run against the mock server from the spec repository.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'stampmitra'

client = StampMitra::Client.new(
  api_key: ENV.fetch('STAMPMITRA_API_KEY'),
  base_url: ENV.fetch('STAMPMITRA_BASE_URL', StampMitra::Client::DEFAULT_BASE_URL)
)

begin
  result = client.verify.pan(pan: ARGV.fetch(0, 'ABCDE1234F'), name: ARGV[1])
  puts "#{result.valid? ? 'valid' : 'invalid'} name-match=#{result.name_match_result.inspect} reference=#{result.reference_id}"
rescue StampMitra::ValidationError => e
  warn "rejected (#{e.field}): #{e.message}"
  exit 2
rescue StampMitra::RateLimitError => e
  warn "slow down, retry in #{e.retry_after || 'a few'} seconds (request #{e.request_id})"
  exit 3
rescue StampMitra::Error => e
  warn "#{e.class}: #{e.message} (request #{e.request_id})"
  exit 1
end
