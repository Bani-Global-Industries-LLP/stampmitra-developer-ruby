# frozen_string_literal: true

require 'test_helper'
require 'support/readme_snippets'

class ReadmeSnippetsTest < Minitest::Test
  RS = ReadmeSnippets

  def factory
    @factory ||= RS.binding_factory(RS::EmptyAdapter.new)
  end

  def run_markdown(markdown)
    outcome = nil
    capture_io { outcome = RS.check(markdown, binding_factory: factory) }
    outcome
  end

  # ---- the real README -------------------------------------------------------------

  def test_every_block_in_the_real_readme_compiles_and_runs
    markdown = File.read(File.join(TestHelper::ROOT, 'README.md'), encoding: 'UTF-8')
    results, failures = run_markdown(markdown)
    assert_empty failures.map { |(block, kind, error)| "README.md:#{block.line} #{kind}: #{error}" }
    kinds = results.map { |(_, kind, _)| kind }
    assert_operator kinds.count(:run_ruby), :>=, 8, 'the fence parser lost executable Ruby blocks (desync?)'
    assert_operator results.size, :>=, 12
    assert_equal markdown.scan(/^ {0,3}(?:`{3,}|~{3,})\S/).size, results.size, 'every opening fence must yield exactly one block'
  end

  def test_the_readme_quickstart_is_the_five_line_version
    markdown = File.read(File.join(TestHelper::ROOT, 'README.md'), encoding: 'UTF-8')
    quickstart = RS.extract(markdown).find { |b| b.code.include?('verify.pan') && b.code.include?("require 'stampmitra'") }
    refute_nil quickstart
    assert_operator quickstart.code.lines.size, :<=, 6
  end

  # ---- the fence parser tolerates formatting quirks and cannot desync ---------------

  def test_trailing_comments_and_flags_in_the_info_string_do_not_shift_blocks
    markdown = <<~MD
      ```ruby   # a comment after the language
      x = 1
      ```
      text between

      ```ruby compile-only title="Gemfile"
      gem 'a'
      ```
      ```bash#{'   '}
      echo hi
      ```
    MD
    blocks = RS.extract(markdown)
    assert_equal %w[ruby ruby bash], blocks.map(&:lang)
    assert_equal ['x = 1', "gem 'a'", 'echo hi'], blocks.map(&:code)
    assert_equal [1, 6, 9], blocks.map(&:line)
    assert_equal ['compile-only', 'title="Gemfile"'], blocks[1].flags
  end

  def test_tilde_fences_longer_fences_and_nested_backticks
    markdown = <<~MD
      ~~~ruby
      puts 1
      ~~~

      ````markdown
      ```ruby
      not a separate block
      ```
      ````

      ```ruby
      puts 2
      ```
    MD
    blocks = RS.extract(markdown)
    assert_equal %w[ruby markdown ruby], blocks.map(&:lang)
    assert_includes blocks[1].code, 'not a separate block'
    assert_equal 'puts 2', blocks[2].code
  end

  def test_indented_fences_inside_lists
    markdown = "1. step\n\n   ```ruby\n   y = 2\n   ```\n"
    blocks = RS.extract(markdown)
    assert_equal 1, blocks.size
    assert_equal 'ruby', blocks[0].lang
  end

  def test_a_comment_line_inside_a_block_that_looks_like_a_fence_does_not_close_it
    markdown = "```ruby\n# ``` not a fence close? it is a comment\nz = 3\n```\n"
    blocks = RS.extract(markdown)
    assert_equal 1, blocks.size
    assert_includes blocks[0].code, 'z = 3'
  end

  def test_an_unterminated_fence_is_an_error
    error = assert_raises(RS::Error) { RS.extract("```ruby\nputs 1\n") }
    assert_match(/unterminated.*line 1/, error.message)
  end

  def test_inline_triple_backticks_are_not_fences
    assert_empty RS.extract("use ```code``` inline\n")
  end

  # ---- failures are reported, never swallowed --------------------------------------------

  def test_syntax_errors_runtime_errors_and_unknown_languages_are_failures
    markdown = <<~MD
      ```ruby
      def broken(
      ```

      ```ruby
      raise 'boom'
      ```

      ```ruby
      client.verify.pan(pan: 'not-a-pan')
      ```

      ```yaml
      a: 1
      ```

      ```
      no language
      ```

      ```json
      {not json}
      ```

      ```bash
      if then
      ```
    MD
    results, failures = run_markdown(markdown)
    assert_equal 7, results.size
    assert_equal 7, failures.size
    errors = failures.map { |(_, _, error)| error }
    assert_match(/syntax error/, errors[0])
    assert_match(/RuntimeError: boom/, errors[1])
    assert_match(/ValidationError/, errors[2])
    assert_match(/no recognised language/, errors[3])
    assert_match(/no recognised language/, errors[4])
    assert_match(/invalid JSON/, errors[5])
    assert_match(/bash -n failed/, errors[6])
  end

  def test_passive_languages_are_ignored_and_compile_only_is_not_executed
    markdown = "```text\nanything goes\n```\n\n```console\n$ ls\n```\n\n```ruby compile-only\nraise 'never runs'\n```\n"
    results, failures = run_markdown(markdown)
    assert_empty failures
    assert_equal %i[ignore ignore compile_ruby], results.map { |(_, kind, _)| kind }
  end

  def test_snippets_cannot_reach_the_real_api
    calls = []
    spy = ->(**request) { calls << request[:url]; { status: 200, headers: {}, body: '{}' } }
    snippets = RS.binding_factory(spy)
    markdown = "```ruby\nStampMitra::Client.new(api_key: 'sk_test_abcdefgh').usage.summary\nclient.usage.summary\n```\n"
    _, failures = RS.check(markdown, binding_factory: snippets)
    assert_empty failures
    assert_equal 2, calls.size
  ensure
    RS.binding_factory(RS::EmptyAdapter.new)
  end

  def test_the_check_script_passes_on_the_readme
    script = File.join(TestHelper::ROOT, 'scripts', 'check-readme-snippets')
    out, status = Open3.capture2e({ 'STAMPMITRA_SPEC_DIR' => '/nonexistent', 'MOCK_SERVER_URL' => '' }, RbConfig.ruby, script)
    assert_predicate status, :success?, out
    assert_match(/blocks: .*run_ruby/, out)
  end
end
