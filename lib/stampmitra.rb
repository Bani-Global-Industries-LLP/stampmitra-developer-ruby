# frozen_string_literal: true

require 'stampmitra/version'
require 'stampmitra/errors'
require 'stampmitra/secret'
require 'stampmitra/redaction'
require 'stampmitra/validators'
require 'stampmitra/request_options'
require 'stampmitra/response'
require 'stampmitra/model'
require 'stampmitra/models'
require 'stampmitra/http_adapter'
require 'stampmitra/transport'
require 'stampmitra/resources/base'
require 'stampmitra/resources/verify'
require 'stampmitra/resources/services'
require 'stampmitra/resources/estamp'
require 'stampmitra/resources/orders'
require 'stampmitra/resources/payments'
require 'stampmitra/resources/usage'
require 'stampmitra/resources/logs'
require 'stampmitra/resources/webhooks'
require 'stampmitra/client'
require 'stampmitra/webhook'

# Official Ruby client for the StampMitra Developer API: Indian identity verification
# (PAN, GSTIN, vehicle RC, Voter ID, driving licence, passport, CIN, Udyam, bank account)
# and e-Stamp Paper.
#
#   client = StampMitra::Client.new(api_key: ENV['STAMPMITRA_API_KEY'])
#   client.verify.pan(pan: 'ABCDE1234F').valid?
#
# See {StampMitra::Client}, {StampMitra::Webhook}, {StampMitra::Validators} and {StampMitra::Error}.
module StampMitra
end
