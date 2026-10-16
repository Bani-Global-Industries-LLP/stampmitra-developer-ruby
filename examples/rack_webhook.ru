# frozen_string_literal: true

# A plain Rack webhook receiver (works under any Rack server and mounts inside Rails/Hanami routers).
#
#   cd examples && bundle install
#   STAMPMITRA_WEBHOOK_SECRET=whsec_... bundle exec rackup rack_webhook.ru -p 9292
require 'json'
require 'stampmitra'

class StampMitraWebhookApp
  def initialize(secret)
    @secret = secret
  end

  def call(env)
    return respond(405, error: 'POST only') unless env['REQUEST_METHOD'] == 'POST'

    payload = env['rack.input'].read # raw bytes, exactly as sent: never parse and re-serialise before verifying
    event = StampMitra::Webhook.construct_event_from_headers(payload: payload, headers: env, secret: @secret)
    env['rack.errors'].puts("#{event.type} #{event.core_order_id} (delivery #{event.event_id})")
    respond(200, received: true, type: event.type)
  rescue StampMitra::SignatureVerificationError => e
    respond(400, error: e.code)
  end

  private

  def respond(status, body)
    [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
  end
end

run StampMitraWebhookApp.new(ENV.fetch('STAMPMITRA_WEBHOOK_SECRET'))
