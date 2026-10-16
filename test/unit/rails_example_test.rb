# frozen_string_literal: true

require 'test_helper'

# Executes examples/rails_webhooks_controller.rb against minimal stand-ins for Rails (no Rails dependency):
# the snippet's own logic - header lookup through request.headers, raw_post verification, dispatch and responses - runs for real.
class RailsExampleTest < Minitest::Test
  SECRET = 'whsec_rails_example'
  PAYLOAD = '{"coreOrderId":"core_1","coreEventType":"DOCUMENT_READY","occurredAt":"2026-10-16T09:00:00.000Z"}'

  class FakeApplicationController
    class << self
      attr_reader :forgery_protection_skipped

      def skip_forgery_protection
        @forgery_protection_skipped = true
      end
    end
    attr_accessor :request, :outcome

    def head(status)
      self.outcome = [:head, status]
    end

    def render(json:, status:)
      self.outcome = [:render, json, status]
    end
  end

  # request.headers in Rails answers [] with the HTTP header name, like this stand-in.
  FakeHeaders = Struct.new(:table) do
    def [](name)
      table[name]
    end
  end
  FakeRequest = Struct.new(:raw_post, :headers)

  class FakeJob
    class << self
      attr_reader :enqueued

      def perform_later(*args)
        (@enqueued ||= []) << args
      end
    end
  end

  module FakeRails
    Credentials = Struct.new(:secret) do
      def dig(*)
        secret
      end
    end
    class << self
      attr_accessor :secret

      def application
        Struct.new(:credentials).new(Credentials.new(secret))
      end

      def logger
        @logger ||= Class.new do
          attr_reader :warnings

          def warn(message)
            (@warnings ||= []) << message
          end
        end.new
      end
    end
  end

  def setup
    FakeRails.secret = SECRET
    FakeJob.instance_variable_set(:@enqueued, nil)
    Object.send(:remove_const, :ApplicationController) if Object.const_defined?(:ApplicationController)
    Object.send(:remove_const, :FetchDocumentsJob) if Object.const_defined?(:FetchDocumentsJob)
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
    Object.send(:remove_const, :StampmitraWebhooksController) if Object.const_defined?(:StampmitraWebhooksController)
    Object.const_set(:ApplicationController, FakeApplicationController)
    Object.const_set(:FetchDocumentsJob, FakeJob)
    Object.const_set(:Rails, FakeRails)
    load File.join(TestHelper::ROOT, 'examples', 'rails_webhooks_controller.rb')
  end

  def teardown
    %i[ApplicationController FetchDocumentsJob Rails StampmitraWebhooksController].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end

  def deliver(payload: PAYLOAD, timestamp: Time.now.to_i, secret: SECRET, headers: nil)
    signature = StampMitra::Webhook.sign(payload: PAYLOAD, timestamp: timestamp, secret: secret)
    controller = StampmitraWebhooksController.new
    controller.request = FakeRequest.new(payload, FakeHeaders.new(headers || { 'X-Webhook-Signature' => signature, 'X-Webhook-Timestamp' => timestamp.to_s,
                                                                               'X-Webhook-Event-Id' => 'evt_77' }))
    controller.create
    controller.outcome
  end

  def test_the_snippet_skips_csrf_protection
    assert StampmitraWebhooksController.forgery_protection_skipped
  end

  def test_a_valid_delivery_enqueues_the_job_and_returns_ok
    assert_equal %i[head ok], deliver
    assert_equal [%w[core_1 evt_77]], FakeJob.enqueued
  end

  def test_a_tampered_body_is_rejected_as_bad_request
    assert_equal [:render, { error: 'SIGNATURE_MISMATCH' }, :bad_request], deliver(payload: PAYLOAD.sub('core_1', 'core_2'))
    assert_nil FakeJob.enqueued
  end

  def test_a_stale_delivery_and_a_wrong_secret_are_rejected
    assert_equal [:render, { error: 'TIMESTAMP_OUTSIDE_TOLERANCE' }, :bad_request], deliver(timestamp: Time.now.to_i - 3600)
    assert_equal [:render, { error: 'SIGNATURE_MISMATCH' }, :bad_request], deliver(secret: 'someone-elses-secret')
  end

  def test_missing_headers_and_missing_credentials
    assert_equal [:render, { error: 'MISSING_HEADERS' }, :bad_request], deliver(headers: {})
    FakeRails.secret = nil
    assert_equal [:render, { error: 'MISSING_SECRET' }, :bad_request], deliver
  end

  def test_failed_orders_are_logged
    payload = '{"coreOrderId":"core_9","coreEventType":"ORDER_FAILED","occurredAt":"2026-10-16T09:00:00.000Z"}'
    now = Time.now.to_i
    controller = StampmitraWebhooksController.new
    controller.request = FakeRequest.new(payload, FakeHeaders.new({ 'X-Webhook-Signature' => StampMitra::Webhook.sign(payload: payload, timestamp: now, secret: SECRET),
                                                                    'X-Webhook-Timestamp' => now.to_s }))
    controller.create
    assert_equal %i[head ok], controller.outcome
    assert_equal ['StampMitra order.failed for core_9'], FakeRails.logger.warnings
  end
end
