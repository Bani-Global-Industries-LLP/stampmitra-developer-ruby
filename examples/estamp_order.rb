# frozen_string_literal: true

# The e-Stamp flow: validate, create (with an idempotency key), upload the payer's PAN card, list the stamps and read a certificate.
#
#   STAMPMITRA_API_KEY=sk_test_... ruby examples/estamp_order.rb [path/to/pan-card.pdf]
#
# An order can be placed without the PAN card, but a PAN card is mandatory to complete the stamp. Set STAMPMITRA_BASE_URL=http://127.0.0.1:4010 to run
# against the mock server from the spec repository.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'stampmitra'

client = StampMitra::Client.new(
  api_key: ENV.fetch('STAMPMITRA_API_KEY'),
  base_url: ENV.fetch('STAMPMITRA_BASE_URL', StampMitra::Client::DEFAULT_BASE_URL)
)

# One order is one state. Parties are a bare name or an object (use the object when the state wants an address or a
# father's / husband's name).
stamps = [{
  client_reference: 'line-001', state: 'MH', article_code: 'ART1', denomination: 1000, purpose: 'Rental Agreement',
  first_party: StampMitra::EstampParty.new(name: 'Jane Doe', address: '12 MG Road, Pune'),
  second_party: 'John Smith'
}]
reference = 'order-2026-0917'

begin
  # Dry run: nothing is created and nothing is billed.
  check = client.estamp.orders.validate(stamps: stamps, reference: reference)
  abort "not valid: #{check.errors.inspect}" unless check.valid
  puts "valid, quote: #{check.quote.inspect}"

  # Creating spends money, so the API requires an Idempotency-Key. Derive yours from something stable you own and
  # persist it before sending; the gem generates one if you leave it out.
  order = client.estamp.orders.create(stamps: stamps, reference: reference, options: { idempotency_key: "#{reference}-v1" })
  puts "created #{order.id} (#{order.status}), #{order.stamp_count} stamp(s)"

  if ARGV[0]
    document = client.estamp.orders.upload_document(order.id, file: ARGV[0], type: 'pan_card')
    puts "uploaded #{document.file_name} (#{document.size_bytes} bytes): #{document.status}"
  end

  client.estamp.orders.list_stamps(order.id).items.each do |stamp|
    certificate = client.estamp.stamps.get_certificate(stamp['id'])
    puts "#{stamp['id']}: certificate #{certificate.available ? "ready (#{certificate.certificate_number})" : certificate.status}"
  end
rescue StampMitra::ValidationError => e
  warn "rejected: #{e.message}"
  e.errors.each { |issue| warn "  #{issue.field} #{issue.code}: #{issue.message}" }
  exit 2
rescue StampMitra::PaymentRequiredError => e
  warn "top up the #{e.wallet || 'wallet'} first (client.wallets), then retry with the same idempotency key"
  exit 3
rescue StampMitra::Error => e
  warn "#{e.class}: #{e.message} (request #{e.request_id})"
  exit 1
end
