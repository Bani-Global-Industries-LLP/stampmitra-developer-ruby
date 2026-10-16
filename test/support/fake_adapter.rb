# frozen_string_literal: true

require 'json'

# An in-memory HTTP adapter: replies with scripted steps and records every call.
# A step is a Hash ({ status:, body:, headers: }), a JSON-able body (200), an Exception instance/class to raise,
# or a Proc receiving the call hash. The last step repeats.
class FakeAdapter
  attr_reader :calls

  def initialize(*steps)
    @steps = steps.empty? ? [{ status: 200, body: {} }] : steps
    @calls = []
  end

  def call(**request)
    @calls << request
    step = @steps[[@calls.size - 1, @steps.size - 1].min]
    step = step.call(request) if step.respond_to?(:call)
    raise step if step.is_a?(Exception)
    raise step.new('fake failure') if step.is_a?(Class) && step <= Exception

    reply(step)
  end

  def bodies
    @calls.map { |call| call[:body] && JSON.parse(call[:body]) }
  end

  def header_values(name)
    @calls.map { |call| call[:headers].find { |key, _| key.casecmp?(name) }&.last }
  end

  private

  def reply(step)
    step = { status: 200, body: step } unless step.is_a?(Hash) && step.key?(:status)
    body = step[:body]
    text = body.is_a?(String) ? body : JSON.generate(body)
    { status: step[:status], headers: { 'content-type' => 'application/json' }.merge(step[:headers] || {}), body: text }
  end
end
