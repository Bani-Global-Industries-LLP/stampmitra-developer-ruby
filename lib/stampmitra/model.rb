# frozen_string_literal: true

require 'json'

module StampMitra
  # Base class of every typed response: an immutable value object built from the
  # API's JSON. Declared attributes are plain readers (snake_case); every field
  # the server sent, including ones this version of the gem does not know about,
  # is preserved and reachable through {#[]} and {#to_h}.
  #
  #   pan = client.verify.pan(pan: 'ABCDE1234F')
  #   pan.valid?              # declared attribute
  #   pan[:brandNewField]     # unknown field, still available
  #   pan.to_h                # the complete decoded body
  class Model
    class << self
      # @return [Hash{Symbol => Hash}] declared attributes (name => key, nested model, list flag)
      def attribute_map
        @attribute_map ||= {}
      end

      # @api private
      def inherited(subclass)
        super
        subclass.attribute_map.merge!(attribute_map)
      end

      # Declares a reader for a JSON field.
      #
      # @param name [Symbol] snake_case reader name
      # @param key [String, nil] JSON key when it differs from the camelCase of +name+
      # @param model [Class, nil] nested {Model} class the value is wrapped in
      # @param list [Boolean] true when the value is an Array of +model+
      # @return [void]
      def attribute(name, key = nil, model: nil, list: false)
        json_key = key || camelize(name.to_s)
        attribute_map[name] = { key: json_key, model: model, list: list }
        define_method(name) { @attributes[name] }
        define_method(:"#{name}?") { @attributes[name] ? true : false } if %i[valid found].include?(name)
      end

      # Builds a model from decoded JSON and attaches the response metadata.
      #
      # @param data [Hash] decoded JSON object
      # @param response [Response, nil]
      # @return [Model]
      def from_hash(data, response: nil)
        new(data, response: response)
      end

      # @api private
      def camelize(name)
        head, *rest = name.split('_')
        head + rest.map(&:capitalize).join
      end
    end

    # @return [Response, nil] HTTP metadata when the model came from an API call
    attr_reader :response

    # @param data [Hash, nil] decoded JSON object (string or symbol keys); may also be given as bare keywords
    # @param response [Response, nil]
    # @param fields [Hash] the object's fields when +data+ is omitted, e.g. +Model.new(valid: true)+
    def initialize(data = nil, response: nil, **fields)
      data = fields if data.nil?
      raise ArgumentError, "#{self.class.name} expects a Hash, got #{data.class}" unless data.is_a?(Hash)

      @data = Model.deep_freeze(Model.stringify(data))
      @response = response
      @attributes = self.class.attribute_map.each_with_object({}) do |(name, spec), out|
        out[name] = coerce(@data[spec[:key]], spec)
      end
    end

    # Reads any field of the response by JSON key or snake_case name, declared or not.
    #
    # @param key [String, Symbol]
    # @return [Object, nil] the raw decoded value
    def [](key)
      name = key.to_s
      return @data[name] if @data.key?(name)

      spec = self.class.attribute_map[name.to_sym]
      spec ? @data[spec[:key]] : nil
    end

    # @param path [Array<String, Symbol, Integer>] keys to follow
    # @return [Object, nil] value found by following +path+ through the raw data
    def dig(*path)
      head, *tail = path
      value = self[head]
      tail.empty? || value.nil? ? value : value.dig(*tail)
    end

    # @return [Hash{String => Object}] a deep copy of the complete decoded body, unknown fields included
    def to_h
      Model.thaw(@data)
    end

    # @return [Array<String>] JSON keys the server sent that this version does not declare
    def unknown_fields
      @data.keys - self.class.attribute_map.values.map { |spec| spec[:key] }
    end

    # @return [String] JSON of the complete body
    def to_json(*args)
      JSON.generate(to_h, *args)
    end

    # @return [Model] a copy carrying +response+
    def with_response(response)
      copy = dup
      copy.instance_variable_set(:@response, response)
      copy
    end

    # @return [Boolean] true when +other+ is the same model class with the same data
    def ==(other)
      other.instance_of?(self.class) && other.to_h == to_h
    end
    alias eql? ==

    # @return [Integer]
    def hash
      [self.class, @data].hash
    end

    # Masks identifiers and removes personal data: responses carry PII.
    # @return [String]
    def inspect
      "#<#{self.class.name} #{Redaction.mask(@data).inspect}>"
    end
    alias to_s inspect

    # @api private
    def self.stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify(v) }
      when Array then value.map { |v| stringify(v) }
      else value
      end
    end

    # @api private
    def self.deep_freeze(value)
      case value
      when Hash then value.each { |k, v| k.freeze && deep_freeze(v) }.freeze
      when Array then value.each { |v| deep_freeze(v) }.freeze
      else value.freeze
      end
    end

    # @api private
    def self.thaw(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), out| out[k.dup] = thaw(v) }
      when Array then value.map { |v| thaw(v) }
      when String then value.dup
      else value
      end
    end

    private

    def coerce(value, spec)
      klass = spec[:model]
      return value unless klass

      if spec[:list]
        if value.is_a?(Array)
          value.map { |item| item.is_a?(Hash) ? klass.new(item) : item }
        else
          value
        end
      else
        value.is_a?(Hash) ? klass.new(value) : value
      end
    end
  end

  # Typed response models, one per named response schema in the OpenAPI spec.
  module Models
    # A response whose shape the API does not fix (e-Stamp reference data, duty
    # calculations, parties, webhook event lists and replays). The decoded JSON is
    # available through {#body}, {#[]}, {#to_h} and, for array roots, {#each}.
    class GenericResponse < Model
      # @return [Object] the decoded JSON (Hash, Array or scalar)
      attr_reader :body

      # @param data [Hash, Array, Object] decoded JSON
      # @param response [Response, nil]
      def initialize(data = {}, response: nil)
        @body = Model.deep_freeze(Model.stringify(data))
        super(@body.is_a?(Hash) ? @body : {}, response: response)
      end

      # @param key [String, Symbol, Integer] a Hash key, or an Array index for array roots
      # @return [Object, nil]
      def [](key)
        if @body.is_a?(Array)
          key.is_a?(Integer) ? @body[key] : nil
        else
          super
        end
      end

      # @return [Array] the items of an array root, or the +items+ field of an object root
      def items
        return @body if @body.is_a?(Array)

        @body.is_a?(Hash) && @body['items'].is_a?(Array) ? @body['items'] : []
      end

      # Iterates {#items}.
      # @yieldparam item [Object]
      # @return [Enumerator, Array]
      def each(&block)
        return items.each unless block

        items.each(&block)
      end
      include Enumerable

      # @return [Hash{String => Object}, Array] a deep copy of the decoded body
      def to_h
        @body.is_a?(Hash) ? Model.thaw(@body) : { 'items' => Model.thaw(@body) }
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} #{Redaction.mask(@body).inspect}>"
      end
      alias to_s inspect
    end
  end
end
