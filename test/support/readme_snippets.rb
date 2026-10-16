# frozen_string_literal: true

require 'json'
require 'open3'
require 'stringio'
require 'stampmitra'

# Extracts every fenced code block from a Markdown file and checks it mechanically:
#
#   ruby            compiled AND executed (with `client` and `request` provided, never touching the real API)
#   ruby compile-only   compiled only (Gemfile lines, framework code that is exercised elsewhere)
#   bash / sh       checked with `bash -n`
#   json            parsed
#   text / console  ignored on purpose
#
# Any other language is a failure, so a block can never be skipped silently. The fence parser is a line-based
# state machine that follows CommonMark rules (backtick or tilde fences of 3+, closing fence at least as long, info
# string may carry flags or a trailing comment, indentation up to 3 spaces), so formatting quirks cannot shift block
# boundaries. An unterminated fence is an error.
module ReadmeSnippets
  Block = Struct.new(:lang, :flags, :info, :code, :line)

  PASSIVE = %w[text console output].freeze
  RUBY = %w[ruby rb].freeze
  SHELL = %w[bash sh shell].freeze
  OPENING = /\A {0,3}(`{3,}|~{3,})[ \t]*([^\n]*)\z/

  class Error < StandardError; end

  module_function

  def extract(markdown)
    blocks = []
    fence = nil
    markdown.each_line.with_index(1) do |raw, number|
      line = raw.chomp
      if fence
        if closing?(line, fence[:marker])
          blocks << Block.new(fence[:lang], fence[:flags], fence[:info], fence[:code].join("\n"), fence[:line])
          fence = nil
        else
          fence[:code] << line
        end
      elsif (m = OPENING.match(line))
        marker = m[1]
        next if marker.start_with?('`') && m[2].include?('`') # inline code such as ```x``` is not a fence

        info = m[2].strip
        words = info.split(/\s+/)
        fence = { marker: marker, lang: words.first.to_s.downcase, flags: words.drop(1), info: info, code: [], line: number }
      end
    end
    raise Error, "unterminated code fence opened at README line #{fence[:line]}" if fence

    blocks
  end

  def closing?(line, marker)
    stripped = line.strip
    stripped.length >= marker.length && stripped.delete(marker[0]).empty? && line.match?(/\A {0,3}\S/)
  end

  # What a block should do; raises for unsupported languages.
  def action(block)
    lang = block.lang
    return :run_ruby if RUBY.include?(lang) && !block.flags.include?('compile-only')
    return :compile_ruby if RUBY.include?(lang)
    return :shell if SHELL.include?(lang)
    return :json if lang == 'json'
    return :ignore if PASSIVE.include?(lang)

    raise Error, "README line #{block.line}: code block has no recognised language (#{block.info.inspect}); use ruby, bash, json or text"
  end

  # Syntax-checks / executes every block. Returns [results, failures]; each result is [block, action, error_or_nil].
  def check(markdown, binding_factory:)
    results = extract(markdown).map do |block|
      kind = action(block)
      [block, kind, run_one(block, kind, binding_factory)]
    rescue Error => e
      [block, :unsupported, e.message]
    end
    [results, results.reject { |(_, _, error)| error.nil? }]
  end

  def run_one(block, kind, binding_factory)
    case kind
    when :compile_ruby then compile(block)
    when :run_ruby then compile(block) || execute(block, binding_factory.call)
    when :shell then shell_syntax(block)
    when :json then json_syntax(block)
    end
  end

  def compile(block)
    RubyVM::InstructionSequence.compile(block.code, "README.md:#{block.line}")
    nil
  rescue SyntaxError => e
    "syntax error: #{e.message.lines.first(3).join.strip}"
  end

  def execute(block, binding_for_block)
    # Line numbers in backtraces point into README.md.
    ClientRouting.routed { eval(block.code, binding_for_block, 'README.md', block.line + 1) } # rubocop:disable Security/Eval
    nil
  rescue StandardError, ScriptError => e
    "#{e.class}: #{e.message.lines.first.to_s.strip} (#{e.backtrace&.find { |l| l.start_with?('README.md') } || 'no README frame'})"
  end

  def shell_syntax(block)
    out, status = Open3.capture2e('bash', '-n', stdin_data: block.code)
    status.success? ? nil : "bash -n failed: #{out.strip}"
  end

  def json_syntax(block)
    JSON.parse(block.code)
    nil
  rescue JSON::ParserError => e
    "invalid JSON: #{e.message.lines.first.strip}"
  end

  # A request stand-in carrying a correctly signed delivery, for the webhook snippet.
  FakeRequest = Struct.new(:body, :env)

  def signed_request(secret)
    payload = '{"coreOrderId":"core_order_1","coreEventType":"ORDER_CREATED","occurredAt":"2026-10-16T09:00:00.000Z"}'
    timestamp = Time.now.to_i
    env = { 'HTTP_X_WEBHOOK_SIGNATURE' => StampMitra::Webhook.sign(payload: payload, timestamp: timestamp, secret: secret),
            'HTTP_X_WEBHOOK_TIMESTAMP' => timestamp.to_s, 'HTTP_X_WEBHOOK_EVENT_ID' => 'evt_readme' }
    FakeRequest.new(StringIO.new(payload), env)
  end

  # Routes every Client created while README snippets run through +adapter+, so nothing can reach the real API.
  # The routing is active only while a snippet runs (see {routed}), so it cannot leak into other tests.
  module ClientRouting
    class << self
      attr_accessor :adapter, :active

      def routed
        previous = active
        self.active = true
        yield
      ensure
        self.active = previous
      end
    end

    def initialize(**options)
      if ClientRouting.active
        super(**options, adapter: ClientRouting.adapter, sleeper: ->(_seconds) {})
      else
        super
      end
    end
  end

  # A binding in which `client` and `request` exist and Client.new is routed to +adapter+.
  def binding_factory(adapter)
    StampMitra::Client.prepend(ClientRouting) unless StampMitra::Client.ancestors.include?(ClientRouting)
    ClientRouting.adapter = adapter
    ENV['STAMPMITRA_API_KEY'] = 'sk_test_readmeExample0001'
    ENV['STAMPMITRA_WEBHOOK_SECRET'] = 'whsec_readme_example'
    lambda do
      scope = Object.new
      b = scope.instance_eval { binding }
      b.local_variable_set(:client, ClientRouting.routed { StampMitra::Client.new })
      b.local_variable_set(:request, signed_request('whsec_readme_example'))
      b
    end
  end

  # Serves minimal canned bodies so snippets that chain calls (create an order, then read it) run without a server.
  class EmptyAdapter
    def call(url:, method:, **)
      path = URI(url).path
      body =
        if method == :post && path == '/v1/orders' then { 'externalOrderId' => 'ord_1', 'createdAt' => '2026-10-16T09:00:00.000Z' }
        elsif path == '/v1/logs' then { 'items' => [], 'nextCursor' => nil }
        elsif path == '/v1/services' then []
        else {}
        end
      { status: 200, headers: {}, body: JSON.generate(body) }
    end
  end

  # Forwards requests to a running mock server instead of the URL in the request (used by scripts/check-readme-snippets).
  class RewritingAdapter
    def initialize(base_url)
      @base = URI(base_url)
      @inner = StampMitra::NetHttpAdapter.new
    end

    def call(url:, **rest)
      target = URI(url)
      target.scheme = @base.scheme
      target.host = @base.host
      target.port = @base.port
      @inner.call(url: target.to_s, **rest)
    end
  end
end
