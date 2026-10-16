# frozen_string_literal: true

require 'json'

# Compares the bundled OpenAPI snapshot (spec/openapi.json) with the METHOD + path pairs the SDK resources
# actually call (api_get / api_post / run with a literal path), so a new API operation without an SDK method
# fails the build.
module SpecCoverage
  HTTP_METHODS = %w[get post put patch delete].freeze

  module_function

  # @return [Array<String>] e.g. "GET /v1/orders/{}"
  def spec_operations(root)
    spec = JSON.parse(File.read(File.join(root, 'spec', 'openapi.json'), encoding: 'UTF-8'))
    spec.fetch('paths').flat_map do |path, item|
      item.keys.select { |m| HTTP_METHODS.include?(m) }.map { |m| "#{m.upcase} #{normalise(path)}" }
    end.sort
  end

  # @return [Array<String>] METHOD + path pairs found in lib/stampmitra/resources
  def sdk_operations(root)
    Dir[File.join(root, 'lib', 'stampmitra', 'resources', '*.rb')].flat_map do |file|
      File.read(file, encoding: 'UTF-8').scan(%r{\bapi_(get|post)\(\s*(["'])(/v1/.*?)\2}).map do |verb, _quote, path|
        "#{verb.upcase} #{normalise(path)}"
      end
    end.uniq.sort
  end

  def missing(root)
    spec_operations(root) - sdk_operations(root)
  end

  def extra(root)
    sdk_operations(root) - spec_operations(root)
  end

  # "/v1/orders/{id}" and "/v1/orders/#{seg(id, :id)}" both become "/v1/orders/{}"
  def normalise(path)
    path.gsub(/\{[^}]*\}/, '{}').gsub(/#\{[^}]*\}/, '{}')
  end
end
