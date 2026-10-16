# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift __dir__

require 'minitest/autorun'
require 'json'
require 'stampmitra'
require 'support/fake_adapter'
require 'support/scripted_server'

module TestHelper
  KEY = 'sk_test_abcdefgh12345678'
  FIXTURES = File.expand_path('fixtures', __dir__)
  ROOT = File.expand_path('..', __dir__)

  # Always read as UTF-8: the default external encoding is US-ASCII under LANG=C (e.g. minimal CI containers).
  def self.json(name)
    JSON.parse(File.read(File.join(FIXTURES, name), encoding: 'UTF-8'))
  end

  def fixture(name)
    TestHelper.json(name)
  end

  # A client wired to a FakeAdapter (no network) with a recording sleeper.
  def fake_client(adapter, **options)
    sleeps = options.delete(:sleeps) || []
    StampMitra::Client.new(api_key: KEY, adapter: adapter, sleeper: ->(seconds) { sleeps << seconds }, **options)
  end
end

Minitest::Test.include(TestHelper)
