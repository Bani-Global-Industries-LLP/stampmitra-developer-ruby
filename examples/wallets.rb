# frozen_string_literal: true

# Reads both wallets (Stamp duty and Service) and the account balance, and (with --topup AMOUNT) starts a Stamp duty top-up.
#
#   STAMPMITRA_API_KEY=sk_test_... ruby examples/wallets.rb [--topup 1000]
#
# The wallet is credited the amount you add. A processing fee plus GST on that fee is added to what the payer pays, and a GST
# tax invoice for the fee is available from client.wallets.stamp_duty.list_invoices. Show your payer the figures the response
# returns: never calculate them yourself, the rate can change.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'stampmitra'

client = StampMitra::Client.new(
  api_key: ENV.fetch('STAMPMITRA_API_KEY'),
  base_url: ENV.fetch('STAMPMITRA_BASE_URL', StampMitra::Client::DEFAULT_BASE_URL)
)

wallets = client.wallets.get
puts "stamp duty: #{wallets.available} available of #{wallets.balance} #{wallets.currency}"
puts "service wallet: #{wallets.service_fee.available} available of #{wallets.service_fee.balance}"
puts "account: #{client.account.balance.state}"

if ARGV[0] == '--topup'
  topup = client.wallets.stamp_duty.topup(base_amount: Float(ARGV.fetch(1)))
  puts "credit #{topup.credit_amount}, fee #{topup.processing_fee_amount} (#{topup.processing_fee_percent}%), " \
       "GST #{topup.gst_amount}, payer pays #{topup.total_charged}"
end
