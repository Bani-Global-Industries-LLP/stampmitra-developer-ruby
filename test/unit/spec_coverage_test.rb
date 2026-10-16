# frozen_string_literal: true

require 'test_helper'
require 'support/spec_coverage'
require 'tmpdir'
require 'fileutils'

class SpecCoverageTest < Minitest::Test
  def test_the_spec_has_31_operations_and_every_one_has_an_sdk_method
    assert_equal 31, SpecCoverage.spec_operations(TestHelper::ROOT).size
    assert_empty SpecCoverage.missing(TestHelper::ROOT), 'spec operations without an SDK method'
    assert_empty SpecCoverage.extra(TestHelper::ROOT), 'SDK paths that are not in the spec'
  end

  def test_the_check_detects_a_missing_operation
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'spec'))
      FileUtils.mkdir_p(File.join(dir, 'lib/stampmitra/resources'))
      spec = JSON.parse(File.read(File.join(TestHelper::ROOT, 'spec/openapi.json'), encoding: 'UTF-8'))
      spec['paths']['/v1/brand-new/{id}'] = { 'get' => { 'operationId' => 'brandNew', 'responses' => {} } }
      File.write(File.join(dir, 'spec/openapi.json'), JSON.generate(spec))
      FileUtils.cp_r(File.join(TestHelper::ROOT, 'lib/stampmitra/resources/.'), File.join(dir, 'lib/stampmitra/resources'))
      assert_equal ['GET /v1/brand-new/{}'], SpecCoverage.missing(dir)
    end
  end

  def test_the_script_exits_non_zero_on_a_gap
    assert system(RbConfig.ruby, File.join(TestHelper::ROOT, 'scripts/check-spec-coverage'), out: File::NULL), 'coverage script should pass'
  end
end
