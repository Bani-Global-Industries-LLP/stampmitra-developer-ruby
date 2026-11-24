# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'tempfile'

# The contract 1.2.0 e-Stamp, wallet and account surface, against an in-memory adapter (no network, no mock server).
class EstampTest < Minitest::Test
  LINE = { state: 'MH', article_code: 'ART1', denomination: 1000, first_party: 'Jane Doe' }.freeze
  PDF = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n"
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  def client_for(*steps, **options)
    @adapter = FakeAdapter.new(*steps)
    @sleeps = []
    fake_client(@adapter, sleeps: @sleeps, **options)
  end

  def call_at(index)
    @adapter.calls[index]
  end

  def path_of(call)
    URI(call[:url]).request_uri
  end

  # ---- routes: every new GET and body-less POST, one table ------------------------------------------------------

  ROUTES = [
    [:get, '/v1/estamp/states/availability?active=true', ->(c) { c.estamp.get_states_availability(active: true) }],
    [:get, '/v1/estamp/states/MH', ->(c) { c.estamp.get_state('MH') }],
    [:get, '/v1/estamp/states/MH/requirements?articleCode=ART1&denomination=500&category=e_stamp',
     ->(c) { c.estamp.get_state_requirements('MH', article_code: 'ART1', denomination: 500, category: :e_stamp) }],
    [:get, '/v1/estamp/states/MH/districts', ->(c) { c.estamp.list_districts('MH') }],
    [:get, '/v1/estamp/states/MH/districts/PUNE/sros', ->(c) { c.estamp.list_sros('MH', 'PUNE') }],
    [:get, '/v1/estamp/orders?page=2&limit=50', ->(c) { c.estamp.orders.list(page: 2, limit: 50) }],
    [:get, '/v1/estamp/orders/estord_1', ->(c) { c.estamp.orders.get('estord_1') }],
    [:get, '/v1/estamp/orders/estord_1/export', ->(c) { c.estamp.orders.export('estord_1') }],
    [:get, '/v1/estamp/orders/estord_1/stamps', ->(c) { c.estamp.orders.list_stamps('estord_1') }],
    [:get, '/v1/estamp/stamps/eststamp_1', ->(c) { c.estamp.stamps.get('eststamp_1') }],
    [:get, '/v1/estamp/stamps/eststamp_1/certificate', ->(c) { c.estamp.stamps.get_certificate('eststamp_1') }],
    [:get, '/v1/estamp/wallet', ->(c) { c.wallets.get }],
    [:get, '/v1/stamp-duty-wallet', ->(c) { c.wallets.stamp_duty.get_balance }],
    [:get, '/v1/stamp-duty-wallet/transactions?limit=5&cursor=c1', ->(c) { c.wallets.stamp_duty.list_transactions(limit: 5, cursor: 'c1') }],
    [:get, '/v1/stamp-duty-wallet/invoices', ->(c) { c.wallets.stamp_duty.list_invoices }],
    [:get, '/v1/stamp-duty-wallet/invoices/inv_1', ->(c) { c.wallets.stamp_duty.get_invoice('inv_1') }],
    [:get, '/v1/service-fee-wallet', ->(c) { c.wallets.service_fee.get_balance }],
    [:get, '/v1/service-fee-wallet/transactions', ->(c) { c.wallets.service_fee.list_transactions }],
    [:get, '/v1/service-fee-wallet/invoices?limit=2', ->(c) { c.wallets.service_fee.list_invoices(limit: 2) }],
    [:get, '/v1/service-fee-wallet/invoices/inv_2', ->(c) { c.wallets.service_fee.get_invoice('inv_2') }],
    [:get, '/v1/account/balance', ->(c) { c.account.balance }],
    [:get, '/v1/account/usage', ->(c) { c.account.usage }]
  ].freeze

  ROUTES.each_with_index do |(verb, path, call), i|
    define_method("test_route_#{i}_#{verb}_#{path[/\A[^?]+/].tr('/', '_')}") do
      client = client_for({ status: 200, body: {} })
      refute_nil call.call(client)
      assert_equal verb, @adapter.calls.first[:method]
      assert_equal path, path_of(call_at(0))
      assert_empty @adapter.header_values('Idempotency-Key').compact, 'GET never carries an Idempotency-Key'
    end
  end

  def test_list_responses_are_enumerable_models
    districts = client_for([{ 'code' => 'PUNE', 'name' => 'Pune' }]).estamp.list_districts('MH')
    assert_equal ['PUNE'], districts.map(&:code)
    sros = client_for([{ 'value' => 'SRO-14', 'label' => 'Pune 14' }]).estamp.list_sros('MH', 'PUNE')
    assert_equal 'SRO-14', sros.first.value
  end

  def test_requirements_expose_the_example_body
    result = client_for({ 'state' => { 'code' => 'MH' }, 'exampleBody' => { 'stamps' => [] } }).estamp.get_state_requirements('MH')
    assert_equal({ 'stamps' => [] }, result.example_body)
  end

  def test_path_ids_are_validated_and_encoded
    client = client_for
    assert_raises(StampMitra::ValidationError) { client.estamp.stamps.get('../x') }
    assert_raises(StampMitra::ValidationError) { client.estamp.get_state('') }
    client.estamp.orders.get('a b')
    assert_equal '/v1/estamp/orders/a%20b', path_of(call_at(0))
  end

  # ---- order create / validate ----------------------------------------------------------------------------------

  def test_create_requires_and_generates_an_idempotency_key_and_reuses_it_on_retry
    client = client_for({ status: 503, body: {} }, { status: 502, body: {} }, { status: 201, body: { 'id' => 'estord_1', 'status' => 'PENDING_REVIEW' } })
    order = client.estamp.orders.create(stamps: [LINE], reference: 'order-1')
    assert_equal 'estord_1', order.id
    keys = @adapter.header_values('Idempotency-Key')
    assert_equal 3, keys.size
    assert_equal 1, keys.uniq.size
    assert_match UUID, keys.first
    assert_equal 201, order.response.status
    assert_equal({ 'reference' => 'order-1', 'stamps' => [{ 'state' => 'MH', 'articleCode' => 'ART1', 'denomination' => 1000, 'firstParty' => 'Jane Doe' }] },
                 @adapter.bodies.first)
  end

  def test_create_uses_the_callers_key_when_given
    client = client_for({ status: 201, body: { 'id' => 'e', 'status' => 'S' } })
    client.estamp.orders.create(stamps: [LINE], options: { idempotency_key: 'lease-2026-0412-v1' })
    assert_equal ['lease-2026-0412-v1'], @adapter.header_values('Idempotency-Key')
  end

  def test_validate_sends_no_key_and_is_retried_because_it_is_a_dry_run
    client = client_for({ status: 503, body: {} }, { status: 200, body: { 'valid' => true, 'errors' => [], 'warnings' => [] } })
    result = client.estamp.orders.validate(stamps: [LINE])
    assert result.valid
    assert_equal 2, @adapter.calls.size
    assert_equal [nil, nil], @adapter.header_values('Idempotency-Key')
  end

  def test_party_forms_struct_types_and_camel_or_snake_hashes_all_serialise_alike
    party = StampMitra::EstampParty.new(name: 'Jane Doe', address: '12 MG Road', father_husband_name: 'R Doe', gender: 'FEMALE')
    area = StampMitra::EstampPropertyArea.new(unit: 'Square Feet', value: 850)
    line = StampMitra::EstampStampLine.new(state: 'MH', article_code: 'ART1', denomination: 1000, first_party: party,
                                           second_party: 'Acme Pvt Ltd', property_area: area, quantity: 2,
                                           pan_card_image: 'https://cdn.example.com/pan.jpg', client_reference: 'line-1')
    hash = { 'state' => 'MH', 'articleCode' => 'ART1', 'denomination' => 1000,
             'firstParty' => { name: 'Jane Doe', address: '12 MG Road', father_husband_name: 'R Doe', gender: 'FEMALE' },
             'secondParty' => 'Acme Pvt Ltd', property_area: { unit: 'Square Feet', value: 850 }, quantity: 2,
             'panCardImage' => 'https://cdn.example.com/pan.jpg', 'clientReference' => 'line-1' }
    client = client_for
    client.estamp.orders.validate(stamps: [line])
    client.estamp.orders.validate(stamps: [hash])
    first, second = @adapter.bodies
    assert_equal first, second
    sent = first['stamps'].first
    assert_equal({ 'name' => 'Jane Doe', 'address' => '12 MG Road', 'fatherHusbandName' => 'R Doe', 'gender' => 'FEMALE' }, sent['firstParty'])
    assert_equal 'Acme Pvt Ltd', sent['secondParty']
    assert_equal({ 'unit' => 'Square Feet', 'value' => 850 }, sent['propertyArea'])
  end

  def local_issues(stamps)
    error = assert_raises(StampMitra::ValidationError) { client_for.estamp.orders.create(stamps: stamps) }
    assert_empty @adapter.calls, 'nothing is sent when the body is invalid'
    error
  end

  def test_local_validation_reports_every_finding_like_the_api_does
    error = local_issues([LINE.merge(state: nil, denomination: 0, first_party: %w[a b], quantity: 1001, pan_card_image: 'http://x.example/p.jpg',
                                     category: 'paper', property_area: { unit: 'sq ft' }, payer_gender: 'X')])
    codes = error.errors.map(&:code)
    assert_equal %w[REQUIRED OUT_OF_RANGE INVALID_VALUE INVALID_VALUE PARTY_MUST_BE_OBJECT INVALID_UNIT HTTPS_URL_REQUIRED OUT_OF_RANGE].sort, codes.sort
    assert_equal 0, error.errors.first.index
    assert_match(/\AVALIDATION_FAILED: /, error.message)
  end

  def test_one_order_is_one_state_and_at_most_5000_stamps
    mixed = local_issues([LINE, LINE.merge(state: 'KA')])
    assert_equal ['MIXED_STATE'], mixed.errors.map(&:code)
    assert_equal 'stamps[1].state', mixed.field
    assert_equal ['TOO_MANY'], local_issues(Array.new(5001) { LINE }).errors.map(&:code)
    assert_equal ['REQUIRED'], local_issues([]).errors.map(&:code)
    assert_equal ['OUT_OF_RANGE'], local_issues([LINE.merge(quantity: 0)]).errors.map(&:code)
    client_for.estamp.orders.validate(stamps: Array.new(5000) { LINE.merge(quantity: 1000) })
    assert_equal 1, @adapter.calls.size
  end

  def test_not_applicable_area_needs_no_value_and_validation_can_be_switched_off
    client_for.estamp.orders.validate(stamps: [LINE.merge(property_area: { unit: 'Not Applicable' })])
    assert_equal 1, @adapter.calls.size
    client = client_for(validate_input: false)
    client.estamp.orders.validate(stamps: [{ state: 'MH' }])
    assert_equal 1, @adapter.calls.size
  end

  # ---- errors: details.errors[] and details.wallet --------------------------------------------------------------

  def test_validation_failures_expose_details_errors
    body = { 'error' => { 'code' => 'BAD_REQUEST', 'message' => 'VALIDATION_FAILED: stamps[0].articleCode: articleCode is required', 'requestId' => 'r1',
                          'details' => { 'errors' => [{ 'field' => 'stamps[0].articleCode', 'code' => 'REQUIRED', 'message' => 'articleCode is required', 'index' => 0 }] } } }
    error = assert_raises(StampMitra::ValidationError) { client_for({ status: 400, body: body }).estamp.orders.create(stamps: [LINE]) }
    assert_equal 'BAD_REQUEST', error.code
    assert_equal body['error']['details'], error.details
    issue = error.errors.first
    assert_equal ['stamps[0].articleCode', 'REQUIRED', 'articleCode is required', 0], [issue.field, issue.code, issue.message, issue.index]
    assert_nil error.wallet
    assert_equal 1, @adapter.calls.size, '400 is never retried'
  end

  def test_payment_required_exposes_the_short_wallet
    body = { 'error' => { 'code' => 'PAYMENT_REQUIRED', 'message' => 'low', 'requestId' => 'r', 'details' => { 'wallet' => 'SERVICE_FEE' } } }
    error = assert_raises(StampMitra::PaymentRequiredError) { client_for({ status: 402, body: body }).estamp.orders.create(stamps: [LINE]) }
    assert_equal 'SERVICE_FEE', error.wallet
    assert_empty error.errors
  end

  def test_errors_without_details_keep_working
    error = assert_raises(StampMitra::NotFoundError) { client_for({ status: 404, body: { 'error' => { 'code' => 'NOT_FOUND', 'message' => 'x' } } }).estamp.orders.get('o') }
    assert_nil error.details
    assert_empty error.errors
    assert_nil error.wallet
  end

  def test_a_422_key_reuse_is_a_validation_error_and_not_retried
    body = { 'error' => { 'code' => 'IDEMPOTENCY_KEY_REUSED', 'message' => 'm', 'requestId' => 'r' } }
    error = assert_raises(StampMitra::ValidationError) { client_for({ status: 422, body: body }, { status: 201, body: {} }).estamp.orders.create(stamps: [LINE]) }
    assert_equal 422, error.status
    assert_equal 'IDEMPOTENCY_KEY_REUSED', error.code
    assert_equal 1, @adapter.calls.size
  end

  # ---- Retry-After and the never-retry set ----------------------------------------------------------------------

  def test_retry_after_is_honoured_on_429_503_and_409_in_progress
    in_progress = { 'error' => { 'code' => 'IDEMPOTENCY_IN_PROGRESS', 'message' => 'm', 'requestId' => 'r' } }
    client = client_for({ status: 429, body: {}, headers: { 'retry-after' => '2' } }, { status: 503, body: {}, headers: { 'retry-after' => '3' } },
                        { status: 409, body: in_progress, headers: { 'retry-after' => '4' } }, { status: 201, body: { 'id' => 'e', 'status' => 'S' } },
                        max_retries: 3)
    client.estamp.orders.create(stamps: [LINE])
    assert_equal [2.0, 3.0, 4.0], @sleeps
    assert_equal 1, @adapter.header_values('Idempotency-Key').uniq.size
  end

  def test_other_409_conflicts_are_never_retried_and_expose_retry_after_when_sent
    body = { 'error' => { 'code' => 'ORDER_NOT_CANCELLABLE', 'message' => 'm', 'requestId' => 'r' } }
    error = assert_raises(StampMitra::ConflictError) { client_for({ status: 409, body: body, headers: { 'retry-after' => '1' } }).estamp.orders.create(stamps: [LINE]) }
    assert_equal 1, @adapter.calls.size
    assert_in_delta 1.0, error.retry_after
  end

  NEVER_RETRIED = {
    'order cancel' => ->(c) { c.estamp.orders.cancel('estord_1') },
    'stamp cancel' => ->(c) { c.estamp.stamps.cancel('eststamp_1') },
    'stamp replace' => ->(c) { c.estamp.stamps.replace('eststamp_1') },
    'pan-card link' => ->(c) { c.estamp.stamps.set_pan_card('eststamp_1', pan_card_image: 'https://cdn.example.com/p.jpg') },
    'stamp duty top-up' => ->(c) { c.wallets.stamp_duty.topup(base_amount: 1000) },
    'service fee top-up' => ->(c) { c.wallets.service_fee.topup(base_amount: 500) },
    'webhook replay' => ->(c) { c.webhooks.events.replay('evt_1') }
  }.freeze

  NEVER_RETRIED.each do |name, call|
    define_method("test_never_retried_#{name.tr(' -', '__')}") do
      [503, 429].each do |status|
        client = client_for({ status: status, body: {}, headers: { 'retry-after' => '1' } }, { status: 200, body: {} })
        assert_raises(StampMitra::Error, name) { call.call(client) }
        assert_equal 1, @adapter.calls.size, "#{name} on #{status}"
      end
      client = client_for(StampMitra::ConnectionError.new('reset'), { status: 200, body: {} })
      assert_raises(StampMitra::ConnectionError) { call.call(client) }
      assert_equal 1, @adapter.calls.size, "#{name} on a connection error"
      assert_empty @sleeps
    end

    define_method("test_never_retried_even_with_a_caller_key_#{name.tr(' -', '__')}") do
      client = client_for({ status: 503, body: {} }, { status: 200, body: {} })
      assert_raises(StampMitra::UpstreamError) { call.call(client) }
      client = client_for({ status: 503, body: {} }, { status: 200, body: {} })
      assert_raises(StampMitra::UpstreamError) do
        if name.include?('webhook') then client.webhooks.events.replay('evt_1', options: { idempotency_key: 'k' })
        else call.call(client)
        end
      end
      assert_equal 1, @adapter.calls.size
    end
  end

  def test_no_never_retried_operation_sends_an_idempotency_key
    NEVER_RETRIED.each_value do |call|
      call.call(client_for)
      assert_equal [nil], @adapter.header_values('Idempotency-Key')
    end
  end

  def test_pan_card_link_returns_the_202_body_and_sends_the_url
    client = client_for({ status: 202, body: { 'stampId' => 'eststamp_1', 'panCard' => { 'status' => 'PROCESSING', 'code' => nil, 'message' => nil } } })
    result = client.estamp.stamps.set_pan_card('eststamp_1', pan_card_image: 'https://cdn.example.com/p.jpg')
    assert_equal 202, result.response.status
    assert_equal 'PROCESSING', result.pan_card.status
    assert_equal({ 'panCardImage' => 'https://cdn.example.com/p.jpg' }, @adapter.bodies.first)
    assert_raises(StampMitra::ValidationError) { client.estamp.stamps.set_pan_card('eststamp_1', pan_card_image: 'http://x.example/p.jpg') }
  end

  # ---- multipart upload -----------------------------------------------------------------------------------------

  def test_upload_sends_a_multipart_body_with_file_and_type_parts_and_a_generated_key
    client = client_for({ status: 201, body: { 'documentId' => 'estdoc_1', 'orderId' => 'estord_1', 'status' => 'RECEIVED' } })
    doc = client.estamp.orders.upload_document('estord_1', file: StringIO.new(PDF), filename: 'pan.pdf', type: 'pan_card')
    assert_equal 'estdoc_1', doc.document_id
    call = call_at(0)
    content_type = call[:headers]['Content-Type']
    boundary = content_type[%r{\Amultipart/form-data; boundary=(\S+)\z}, 1]
    refute_nil boundary
    body = call[:body]
    assert_equal Encoding::BINARY, body.encoding
    assert body.start_with?("--#{boundary}\r\n")
    assert body.end_with?("--#{boundary}--\r\n")
    assert_includes body, "Content-Disposition: form-data; name=\"file\"; filename=\"pan.pdf\"\r\nContent-Type: application/pdf\r\n\r\n#{PDF}\r\n"
    assert_includes body, "Content-Disposition: form-data; name=\"type\"\r\n\r\npan_card\r\n"
    assert_match UUID, call[:headers]['Idempotency-Key']
    assert_equal '/v1/estamp/orders/estord_1/documents', URI(call[:url]).path
  end

  def test_upload_reads_a_path_and_omits_the_type_part_unless_given
    Tempfile.create(['pan', '.png']) do |file|
      file.binmode
      file.write("\x89PNG\r\n\x1a\ndata".b)
      file.flush
      client = client_for({ status: 201, body: {} })
      client.estamp.orders.upload_document('estord_1', file: file.path)
      body = call_at(0)[:body]
      assert_includes body, "filename=\"#{File.basename(file.path)}\"\r\nContent-Type: image/png"
      refute_includes body, 'name="type"'
    end
  end

  def test_upload_retries_resend_the_same_body_and_key
    client = client_for({ status: 502, body: {} }, { status: 201, body: {} })
    client.estamp.orders.upload_document('estord_1', file: StringIO.new(PDF), filename: 'pan.pdf')
    assert_equal 2, @adapter.calls.size
    assert_equal @adapter.calls[0][:body], @adapter.calls[1][:body]
    assert_equal 1, @adapter.header_values('Idempotency-Key').uniq.size
    refute_nil @adapter.header_values('Idempotency-Key').first
  end

  def test_upload_400_is_not_retried_and_keeps_the_server_code
    body = { 'error' => { 'code' => 'FILE_CONTENT_MISMATCH', 'message' => 'm', 'requestId' => 'r' } }
    error = assert_raises(StampMitra::ValidationError) do
      client_for({ status: 400, body: body }, { status: 201, body: {} }).estamp.orders.upload_document('o', file: StringIO.new(PDF), filename: 'a.pdf')
    end
    assert_equal 'FILE_CONTENT_MISMATCH', error.code
    assert_equal 1, @adapter.calls.size
  end

  def test_upload_checks_the_file_locally_before_sending_anything
    client = client_for
    big = StringIO.new('a' * ((10 * 1024 * 1024) + 1))
    assert_equal 'FILE_TOO_LARGE', assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: big, filename: 'a.pdf') }.code
    assert_equal 'UNSUPPORTED_FILE_TYPE', assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: StringIO.new('x'), filename: 'a.txt') }.code
    assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: StringIO.new('')) }
    assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: StringIO.new(PDF), filename: 'a.pdf', type: 'selfie') }
    assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: '/no/such/file.pdf') }
    assert_raises(StampMitra::ValidationError) { client.estamp.orders.upload_document('o', file: 42) }
    assert_empty @adapter.calls
  end

  def test_filename_quotes_and_line_breaks_cannot_break_the_part_header
    client_for.estamp.orders.upload_document('o', file: StringIO.new(PDF), filename: "a\"b\r\nc.pdf")
    assert_includes call_at(0)[:body], 'filename="a%22b%0D%0Ac.pdf"'
  end

  def test_multipart_bodies_never_reach_the_debug_log
    log = StringIO.new
    client = client_for(logger: Logger.new(log, level: Logger::DEBUG))
    client.estamp.orders.upload_document('o', file: StringIO.new(PDF), filename: 'a.pdf')
    refute_includes log.string, '%PDF'
    assert_includes log.string, '[multipart/form-data,'
  end

  # ---- wallets: amounts are read from the response, never computed ----------------------------------------------

  def test_stamp_duty_topup_types_and_no_local_fee_calculation
    body = { 'baseAmount' => 1000, 'processingFeePercent' => '6.00', 'processingFeeAmount' => '60.00', 'gstAmount' => 10.8, 'totalCharged' => 1070.8,
             'creditAmount' => '1000.00', 'razorpayOrderId' => 'order_x' }
    topup = client_for({ status: 201, body: body }).wallets.stamp_duty.topup(base_amount: 1000)
    assert_equal({ 'baseAmount' => 1000 }, @adapter.bodies.first)
    assert_kind_of Numeric, topup.base_amount
    assert_kind_of Float, topup.gst_amount
    assert_kind_of Float, topup.total_charged
    assert_equal ['6.00', '60.00', '1000.00'], [topup.processing_fee_percent, topup.processing_fee_amount, topup.credit_amount]
    assert_nil topup.topup_id
    assert_equal 'order_x', topup.razorpay_order_id
  end

  def test_the_fee_figures_are_whatever_the_server_returned
    body = { 'baseAmount' => 1000, 'processingFeePercent' => '7.00', 'processingFeeAmount' => '70.00', 'gstAmount' => 12.6, 'totalCharged' => 1082.6,
             'creditAmount' => '1000.00', 'topupId' => 'cmwtopup1' }
    topup = client_for(body).wallets.stamp_duty.topup(base_amount: 1000)
    assert_in_delta(1082.6, topup.total_charged)
    assert_equal 'cmwtopup1', topup.topup_id
  end

  def test_service_fee_topup_amounts_are_strings
    body = { 'baseAmount' => '500.00', 'gstAmount' => '90.00', 'processingFeePercent' => '0.00', 'processingFeeAmount' => '0.00', 'creditAmount' => '500.00',
             'totalCharged' => '590.00' }
    topup = client_for(body).wallets.service_fee.topup(base_amount: 500.5)
    assert_equal({ 'baseAmount' => 500.5 }, @adapter.bodies.first)
    assert_equal '590.00', topup.total_charged
  end

  def test_topup_amount_validation
    wallet = client_for.wallets.stamp_duty
    [0, -5, '100', nil, Float::NAN, Float::INFINITY].each do |bad|
      assert_raises(StampMitra::ValidationError, bad.inspect) { wallet.topup(base_amount: bad) }
    end
    assert_empty @adapter.calls
  end

  def test_pagination_follows_next_cursor_for_orders_and_wallet_lists
    page1 = { 'items' => [{ 'id' => 'a', 'status' => 'S' }], 'nextCursor' => 'c1' }
    page2 = { 'items' => [{ 'id' => 'b', 'status' => 'S' }], 'nextCursor' => nil }
    client = client_for(page1, page2)
    assert_equal %w[a b], client.estamp.orders.each(limit: 1).map(&:id)
    assert_nil URI.decode_www_form(URI(call_at(0)[:url]).query.to_s).to_h['cursor']
    assert_equal 'c1', URI.decode_www_form(URI(call_at(1)[:url]).query.to_s).to_h['cursor']

    tx = { 'items' => [{ 'id' => 't1' }], 'nextCursor' => nil }
    assert_equal ['t1'], client_for(tx).wallets.service_fee.each_transaction.map(&:id)
    assert_equal ['t1'], client_for(tx).wallets.stamp_duty.each_invoice.map(&:id)
  end

  def test_validate_order_status_wallet_and_account_models
    wallet = client_for({ 'balance' => '10.00', 'held' => '1.00', 'available' => '9.00', 'currency' => 'INR', 'mode' => 'live', 'simulated' => false,
                          'serviceFee' => { 'balance' => '2.00', 'held' => '0.00', 'available' => '2.00' } }).wallets.get
    assert_equal '2.00', wallet.service_fee.balance
    assert_instance_of StampMitra::Models::EstampWalletPart, wallet.service_fee
    order = client_for({ 'id' => 'estord_1', 'status' => 'P', 'counts' => { 'total' => 2, 'e_stamp' => 2 }, 'stamps' => [{ 'id' => 's1', 'clientReference' => 'l1' }] }).estamp.orders.get('estord_1')
    assert_equal 2, order.counts.total
    assert_equal 'l1', order.stamps.first.client_reference
  end

  def test_with_response_view_covers_the_new_resources
    client = client_for({ 'balance' => '1.00', 'currency' => 'INR' })
    data, response = client.with_response.wallets.stamp_duty.get_balance
    assert_equal '1.00', data.balance
    assert_equal 200, response.status
  end

  def test_personal_data_is_masked_in_logs_of_order_bodies
    log = StringIO.new
    client = client_for(logger: Logger.new(log, level: Logger::DEBUG))
    client.estamp.orders.validate(stamps: [LINE.merge(first_party: { name: 'Jane Doe', address: '12 MG Road', phone: '9876543210' }, payer_phone: '9123456780')])
    refute_includes log.string, 'Jane Doe'
    refute_includes log.string, '12 MG Road'
    refute_includes log.string, '9876543210'
  end
end
