# frozen_string_literal: true

# Creates an order and reads it back. Orders are addressed by YOUR externalOrderId (the response has no "id").
#
#   STAMPMITRA_API_KEY=sk_test_... ruby examples/create_order.rb
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'securerandom'
require 'stampmitra'

client = StampMitra::Client.new(
  api_key: ENV.fetch('STAMPMITRA_API_KEY'),
  base_url: ENV.fetch('STAMPMITRA_BASE_URL', StampMitra::Client::DEFAULT_BASE_URL)
)

# An Idempotency-Key is generated for you and reused across automatic retries. Pass your own
# (options: { idempotency_key: }) when YOU retry, e.g. after a crash, so the order is not created twice.
order = client.orders.create(
  external_order_id: "order-#{SecureRandom.hex(6)}",
  external_customer_id: 'customer-1',
  service_code: 'estamp.instrument.rent_agreement',
  details: { 'stateCode' => 'MH' }
)
puts "created #{order.external_order_id} at #{order.created_at}"

# Use externalOrderId with get / get_status / list_documents.
status = client.orders.get_status(order.external_order_id)
puts "status: #{status.status.inspect}"

# Raw response metadata (status, headers, request id, attempts) is available on every result.
documents, response = client.with_response.orders.list_documents(order.external_order_id)
puts "documents: #{documents.documents.inspect} (HTTP #{response.status}, #{response.attempts} attempt(s))"
