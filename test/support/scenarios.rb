# frozen_string_literal: true

# Maps the shared retry-scenarios.json entries onto public SDK calls (used by unit and conformance tests).
module Scenarios
  # Maps method + path of a scenario to the public resource call that produces it. Scenarios that describe a POST
  # WITHOUT an Idempotency-Key exercise the transport contract directly ("a keyless POST is never auto-retried"):
  # the resource methods always attach a generated key, so they cannot express a keyless POST.
  def perform(client, scenario, options)
    path = scenario['path']
    return keyless_post(client, scenario, options) if scenario['method'] == 'POST' && scenario['idempotencyKey'] == false

    case [scenario['method'], path.sub(%r{/(ord_1|missing|evt_1)}, '/ID')]
    when ['GET', '/v1/services'] then client.services.list(options: options)
    when ['GET', '/v1/usage/summary'] then client.usage.summary(options: options)
    when ['GET', '/v1/logs'] then client.logs.list(options: options)
    when ['GET', '/v1/orders/ID'] then client.orders.get(path.split('/').last, options: options)
    when ['GET', '/v1/orders/ID/status'] then client.orders.get_status('ord_1', options: options)
    when ['POST', '/v1/orders'] then client.orders.create(external_order_id: 'o', external_customer_id: 'c', service_code: 's', options: options)
    when ['POST', '/v1/payments/intents']
      client.payments.intents.create(external_order_id: 'o', amount_minor: 100, currency: 'INR', payment_connection_id: 'p', options: options)
    when ['POST', '/v1/estamp/orders/ID/parties'] then client.estamp.add_parties('ord_1', party_name: 'B', options: options)
    when ['POST', '/v1/verify/pan'] then client.verify.pan(pan: 'ABCDE1234F', options: options)
    else flunk "no mapping for #{scenario['method']} #{path}"
    end
  end

  def keyless_post(client, scenario, options)
    transport = client.verify.send(:transport)
    transport.request(:post, scenario['path'], body: {}, options: options, idempotent: false)
  end

  def check_outcome(outcome, result, error)
    if outcome.is_a?(Integer)
      assert_nil error, error&.message
      refute_nil result
      return
    end
    refute_nil error, "expected #{outcome}"
    klass = outcome[/\A[A-Za-z]+/].sub('PermissionError', 'PermissionDeniedError')
    assert_equal "StampMitra::#{klass}", error.class.name
    assert_equal outcome[/\((\d{3})\)/, 1].to_i, error.status if outcome =~ /\(\d{3}\)/
    assert_in_delta outcome[/retryAfter=(\d+)/, 1].to_f, error.retry_after if outcome.include?('retryAfter')
  end

  def check_keys(scenario, keys)
    if scenario['sameIdempotencyKeyAcrossAttempts']
      assert_equal 1, keys.uniq.size
      refute_nil keys.first
      assert_equal 'caller-key-1', keys.first if scenario['idempotencyKey'] == true
    end
    assert_empty(keys.compact, scenario['name']) if scenario['idempotencyKey'] == false
  end
end
