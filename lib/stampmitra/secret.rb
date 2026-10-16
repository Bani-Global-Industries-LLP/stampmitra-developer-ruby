# frozen_string_literal: true

module StampMitra
  # Holds a credential so it cannot leak through +inspect+, +to_s+, string
  # interpolation, +pp+, YAML or Marshal. Use {#reveal} at the single point
  # where the value is actually needed.
  # @api private
  class Secret
    # @param value [String]
    def initialize(value)
      @value = value.to_s.dup.freeze
    end

    # @return [String] the secret value
    def reveal
      @value
    end

    # @return [Boolean] true when the secret is empty
    def empty?
      @value.empty?
    end

    # @return [String]
    def to_s
      '[REDACTED]'
    end

    # @return [String]
    def inspect
      '#<StampMitra::Secret [REDACTED]>'
    end

    # @return [String]
    def to_json(*)
      '"[REDACTED]"'
    end

    # @return [Hash]
    def to_h
      { redacted: true }
    end

    # Secrets are never serialised.
    # @raise [TypeError]
    def marshal_dump
      raise TypeError, 'StampMitra::Secret cannot be serialised'
    end

    # @api private
    def encode_with(coder)
      coder.scalar = '[REDACTED]'
    end
  end
end
