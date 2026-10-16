# frozen_string_literal: true

require 'test_helper'
require 'open3'

# Every example and script must at least parse; scripts/run-examples executes the runnable ones against the mock server and
# test/unit/rails_example_test.rb executes the Rails controller.
class ExamplesSyntaxTest < Minitest::Test
  FILES = Dir[File.join(TestHelper::ROOT, 'examples', '*.{rb,ru}')] + Dir[File.join(TestHelper::ROOT, 'scripts', '*')]

  def test_there_are_examples_for_plain_script_sinatra_rack_and_rails
    names = FILES.map { |f| File.basename(f) }
    %w[verify_pan.rb create_order.rb list_logs.rb sinatra_webhook.rb rack_webhook.ru rails_webhooks_controller.rb].each do |name|
      assert_includes names, name
    end
  end

  FILES.each do |file|
    define_method("test_syntax_#{File.basename(file).tr('.-', '__')}") do
      out, status = Open3.capture2e(RbConfig.ruby, '-c', file)
      assert_equal 0, status.exitstatus, out
    end
  end
end
