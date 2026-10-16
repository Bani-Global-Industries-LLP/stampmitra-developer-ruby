# frozen_string_literal: true

# app/controllers/stampmitra_webhooks_controller.rb (Rails 6.1+)
#
# config/routes.rb:   post '/webhooks/stampmitra', to: 'stampmitra_webhooks#create'
# config/credentials: stampmitra: { webhook_secret: whsec_... }
#
# Webhooks are server-to-server calls without a CSRF token or session, so both are skipped here. The signature is
# the only authentication: verify it against request.raw_post (the bytes as received), never against params.
class StampmitraWebhooksController < ApplicationController
  skip_forgery_protection

  def create
    event = StampMitra::Webhook.construct_event_from_headers(
      payload: request.raw_post,
      headers: request.headers,
      secret: Rails.application.credentials.dig(:stampmitra, :webhook_secret)
    )

    case event
    when StampMitra::Webhook::OrderDocumentReady
      FetchDocumentsJob.perform_later(event.core_order_id, event.event_id)
    when StampMitra::Webhook::OrderFailed, StampMitra::Webhook::OrderCancelled
      Rails.logger.warn("StampMitra #{event.type} for #{event.core_order_id}")
    end

    head :ok
  rescue StampMitra::SignatureVerificationError => e
    render json: { error: e.code }, status: :bad_request
  end
end
