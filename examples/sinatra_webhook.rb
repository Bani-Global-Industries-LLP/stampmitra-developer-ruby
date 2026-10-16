# frozen_string_literal: true

# A Sinatra webhook receiver.
#
#   cd examples && bundle install
#   STAMPMITRA_WEBHOOK_SECRET=whsec_... bundle exec ruby sinatra_webhook.rb -p 4567
require 'sinatra'
require 'stampmitra'

SECRET = ENV.fetch('STAMPMITRA_WEBHOOK_SECRET')

post '/webhooks/stampmitra' do
  payload = request.body.read # the RAW body: never JSON.parse and re-serialise before verifying
  begin
    event = StampMitra::Webhook.construct_event_from_headers(payload: payload, headers: request.env, secret: SECRET)
  rescue StampMitra::SignatureVerificationError => e
    halt 400, "invalid webhook: #{e.code}"
  end

  case event
  when StampMitra::Webhook::OrderDocumentReady
    logger.info("documents ready for #{event.core_order_id}")
  when StampMitra::Webhook::OrderFailed, StampMitra::Webhook::OrderCancelled
    logger.warn("#{event.type} for #{event.core_order_id}")
  else
    logger.info("#{event.type || event.core_event_type} for #{event.core_order_id}")
  end

  status 200 # acknowledge quickly; do slow work in a background job keyed by event.event_id
  'ok'
end
