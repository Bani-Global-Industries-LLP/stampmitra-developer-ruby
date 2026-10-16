# frozen_string_literal: true

require 'test_helper'

class ModelsTest < Minitest::Test
  SPEC = JSON.parse(File.read(File.join(TestHelper::ROOT, 'spec', 'openapi.json'), encoding: 'UTF-8'))

  def class_for(schema)
    source = File.read(File.join(TestHelper::ROOT, 'scripts', 'generate-models'), encoding: 'UTF-8')
    mapping = source[/CLASSES = \{(.*?)\}\.freeze/m, 1].scan(/'(\w+)' => '(\w+)'/).to_h
    StampMitra::Models.const_get(mapping.fetch(schema))
  end

  def test_every_named_response_schema_has_a_model_declaring_exactly_its_properties
    source = File.read(File.join(TestHelper::ROOT, 'scripts', 'generate-models'), encoding: 'UTF-8')
    schemas = source[/CLASSES = \{(.*?)\}\.freeze/m, 1].scan(/'(\w+)' => '\w+'/).flatten
    assert_operator schemas.size, :>=, 25
    schemas.each do |schema|
      klass = class_for(schema)
      declared = klass.attribute_map.values.map { |spec| spec[:key] }.sort
      assert_equal SPEC['components']['schemas'][schema]['properties'].keys.sort, declared, schema
    end
  end

  def test_schemas_with_no_fixed_shape_use_generic_response
    %w[EstampSchemaResponse EstampStatesResponse EstampInstrumentsResponse EstampArticlesResponse EstampDutyCalculation EstampPartiesResponse
       WebhookEventsPage WebhookReplayResponse].each do |name|
      assert_nil SPEC['components']['schemas'][name]['properties'], name
    end
  end

  def pan_data
    { 'referenceId' => 'SMV-1', 'pan' => 'ABCDE1234F', 'valid' => false, 'registeredName' => 'X', 'brandNewField' => { 'x' => [1, 2] } }
  end

  def test_declared_attributes_unknown_fields_and_raw_access
    model = StampMitra::Models::PanVerification.new(pan_data)
    assert_equal 'SMV-1', model.reference_id
    refute model.valid
    refute_predicate model, :valid?
    assert_nil model.father_name
    assert_equal({ 'x' => [1, 2] }, model['brandNewField'])
    assert_equal({ 'x' => [1, 2] }, model[:brandNewField])
    assert_equal 'SMV-1', model[:reference_id]
    assert_equal 'SMV-1', model['referenceId']
    assert_nil model[:nope]
    assert_equal 2, model.dig(:brandNewField, 'x', 1)
    assert_equal ['brandNewField'], model.unknown_fields
    assert_equal pan_data, model.to_h
  end

  def test_symbol_keys_are_accepted_when_building_models
    assert_equal 'SMV-1', StampMitra::Models::PanVerification.new(referenceId: 'SMV-1').reference_id
  end

  def test_models_are_immutable_and_to_h_returns_a_copy
    model = StampMitra::Models::PanVerification.new(pan_data)
    copy = model.to_h
    copy['referenceId'] = 'changed'
    copy['brandNewField']['x'] << 3
    assert_equal 'SMV-1', model.reference_id
    assert_equal [1, 2], model['brandNewField']['x']
    assert_raises(FrozenError) { model.reference_id << 'x' }
    assert_raises(FrozenError) { model['brandNewField']['x'] << 3 }
  end

  def test_equality_hash_and_json
    a = StampMitra::Models::PanVerification.new(pan_data)
    b = StampMitra::Models::PanVerification.new(pan_data)
    assert_equal a, b
    assert_equal a.hash, b.hash
    assert_equal(1, { a => 1 }[b])
    refute_equal a, StampMitra::Models::PanVerification.new(pan_data.merge('valid' => true))
    refute_equal a, StampMitra::Models::GstinVerification.new(pan_data)
    assert_equal pan_data, JSON.parse(a.to_json)
  end

  def test_inspect_and_to_s_mask_personal_data
    text = StampMitra::Models::PanVerification.new(pan_data).inspect
    refute_includes text, 'ABCDE1234F'
    assert_includes text, '******234F'
    assert_includes text, '[REDACTED]'
    assert_equal text, StampMitra::Models::PanVerification.new(pan_data).to_s
  end

  def test_nested_models_and_lists
    cin = StampMitra::Models::CinVerification.new('referenceId' => 'r', 'valid' => true, 'directors' => [{ 'din' => '1', 'name' => 'A', 'designation' => 'D', 'x' => 1 }])
    assert_instance_of StampMitra::Models::CinDirector, cin.directors.first
    assert_equal 'A', cin.directors.first.name
    assert_equal 1, cin.directors.first[:x]
    bank = StampMitra::Models::BankAccountVerification.new('referenceId' => 'r', 'valid' => true, 'ifscDetails' => { 'bank' => 'ICICI', 'ifsc' => 'ICIC0001234' })
    assert_equal 'ICICI', bank.ifsc_details.bank
    gst = StampMitra::Models::PanToGstin.new('gstins' => [{ 'gstin' => '27A', 'state' => 'MH', 'status' => 'Active' }])
    assert_equal 'MH', gst.gstins.first.state
    page = StampMitra::Models::LogsPage.new('items' => [{ 'id' => 'a' }, { 'id' => 'b' }], 'nextCursor' => 'c')
    assert_equal %w[a b], page.items.map(&:id)
    assert_equal 'c', page.next_cursor
    assert_nil StampMitra::Models::CinVerification.new({}).directors
  end

  def test_unexpected_shapes_do_not_raise
    assert_equal 'oops', StampMitra::Models::CinVerification.new('directors' => 'oops').directors
    assert_equal ['x'], StampMitra::Models::CinVerification.new('directors' => ['x']).directors
    assert_equal 5, StampMitra::Models::BankAccountVerification.new('ifscDetails' => 5).ifsc_details
    assert_equal({}, StampMitra::Models::PanVerification.new(nil).to_h)
    assert_raises(ArgumentError) { StampMitra::Models::PanVerification.new([1]) }
  end

  def test_gstin_uses_the_uppercase_wire_key
    model = StampMitra::Models::GstinVerification.new('referenceId' => 'r', 'GSTIN' => '27ABCDE1234F1Z5', 'valid' => true)
    assert_equal '27ABCDE1234F1Z5', model.gstin
    assert_predicate model, :valid?
  end

  def test_found_predicate
    assert_predicate StampMitra::Models::UdyamVerification.new('found' => true), :found?
    refute_predicate StampMitra::Models::PanToUdyam.new('found' => false), :found?
  end

  def test_with_response_attaches_metadata_without_mutating
    model = StampMitra::Models::PanVerification.new(pan_data)
    response = StampMitra::Response.new(status: 200, headers: { 'x-request-id' => 'r1' }, body: '{}')
    with = model.with_response(response)
    assert_nil model.response
    assert_equal 'r1', with.response.request_id
    assert_equal model, with
  end

  def test_the_generated_models_file_is_up_to_date
    assert system(RbConfig.ruby, File.join(TestHelper::ROOT, 'scripts', 'generate-models'), '--check', out: File::NULL), 'run scripts/generate-models'
  end
end
