# frozen_string_literal: true

require 'test_helper'

class PaginationTest < Minitest::Test
  def page(ids, next_cursor)
    { status: 200, body: { 'items' => ids.map { |id| { 'id' => id, 'createdAt' => '2026-10-15T09:41:07.000Z', 'actorType' => 'api_key', 'service' => 'pan.verify' } },
                           'nextCursor' => next_cursor } }
  end

  def three_pages
    FakeAdapter.new(page(%w[a b], 'c1'), page(%w[c d], 'c2'), page(%w[e], nil))
  end

  def cursors(adapter)
    adapter.calls.map { |call| URI.decode_www_form(URI(call[:url]).query.to_s).to_h['cursor'] }
  end

  def test_each_follows_next_cursor_across_three_pages
    adapter = three_pages
    ids = []
    fake_client(adapter).logs.each(limit: 2) { |entry| ids << entry.id }
    assert_equal %w[a b c d e], ids
    assert_equal [nil, 'c1', 'c2'], cursors(adapter)
    assert(adapter.calls.all? { |c| URI.decode_www_form(URI(c[:url]).query).to_h['limit'] == '2' })
  end

  def test_each_returns_an_enumerator_without_a_block_and_makes_no_request_until_iterated
    adapter = three_pages
    enum = fake_client(adapter).logs.each(service: 'pan.verify')
    assert_kind_of Enumerator, enum
    assert_empty adapter.calls
    assert_equal %w[a b c d e], enum.map(&:id)
  end

  def test_enumerator_is_lazy_and_stops_fetching_early
    adapter = three_pages
    first = fake_client(adapter).logs.each(limit: 2).lazy.map(&:id).first(3)
    assert_equal %w[a b c], first
    assert_equal 2, adapter.calls.size, 'the third page must not be fetched'

    adapter = three_pages
    assert_equal %w[a], fake_client(adapter).logs.each.first(1).map(&:id)
    assert_equal 1, adapter.calls.size
  end

  def test_enumerator_supports_ruby_enumerable_methods
    enum = fake_client(three_pages).logs.each
    assert_equal 5, enum.count
    assert_equal 'e', fake_client(three_pages).logs.each.to_a.last.id
    assert_equal %w[a c e], fake_client(three_pages).logs.each.each_slice(2).map { |s| s.first.id }
    assert_equal %w[a b], fake_client(three_pages).logs.each.take_while { |e| e.id < 'c' }.map(&:id)
  end

  def test_starting_cursor_is_honoured
    adapter = FakeAdapter.new(page(%w[x], nil))
    fake_client(adapter).logs.each(cursor: 'start') { |_| nil }
    assert_equal ['start'], cursors(adapter)
  end

  def test_each_page_yields_pages
    pages = fake_client(three_pages).logs.each_page.map { |p| p.items.map(&:id) }
    assert_equal [%w[a b], %w[c d], %w[e]], pages
  end

  def test_empty_string_cursor_ends_iteration
    adapter = FakeAdapter.new(page(%w[a], ''))
    assert_equal %w[a], fake_client(adapter).logs.each.map(&:id)
    assert_equal 1, adapter.calls.size
  end

  def test_a_repeated_cursor_raises_instead_of_looping_forever
    adapter = FakeAdapter.new(page(%w[a], 'same'))
    error = assert_raises(StampMitra::Error) { fake_client(adapter).logs.each.to_a }
    assert_equal 'PAGINATION_LOOP', error.code
    assert_equal 2, adapter.calls.size
  end

  def test_errors_mid_iteration_propagate_after_earlier_items
    adapter = FakeAdapter.new(page(%w[a], 'c1'), { status: 404, body: { 'error' => { 'code' => 'NOT_FOUND', 'message' => 'gone' } } })
    seen = []
    assert_raises(StampMitra::NotFoundError) { fake_client(adapter, max_retries: 0).logs.each { |e| seen << e.id } }
    assert_equal %w[a], seen
  end

  def test_per_request_options_apply_to_every_page
    adapter = three_pages
    fake_client(adapter).logs.each(options: { headers: { 'X-T' => '1' } }) { |_| nil }
    assert_equal %w[1 1 1], adapter.header_values('X-T')
  end

  def test_each_works_on_the_with_response_view
    ids = fake_client(three_pages).with_response.logs.each.map(&:id)
    assert_equal %w[a b c d e], ids
  end

  def test_list_returns_a_typed_page
    result = fake_client(three_pages).logs.list(limit: 2)
    assert_instance_of StampMitra::Models::LogsPage, result
    assert_equal 'c1', result.next_cursor
    assert_equal 'a', result.items.first.id
  end
end
