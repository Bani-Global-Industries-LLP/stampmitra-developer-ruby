# frozen_string_literal: true

# Walks the API call logs with lazy cursor pagination.
#
#   STAMPMITRA_API_KEY=sk_test_... ruby examples/list_logs.rb
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'stampmitra'

client = StampMitra::Client.new(
  api_key: ENV.fetch('STAMPMITRA_API_KEY'),
  base_url: ENV.fetch('STAMPMITRA_BASE_URL', StampMitra::Client::DEFAULT_BASE_URL)
)

# logs.each returns an Enumerator; pages are fetched on demand, so .first(25) stops after the pages it needs.
client.logs.each(service: 'pan.verify', status: 'success', limit: 100).lazy.first(25).each do |entry|
  puts "#{entry.created_at} #{entry.service} #{entry.id}"
end

# Or work page by page (each_page also returns an Enumerator):
page = client.logs.each_page(limit: 50).first
puts "page of #{page.items.size}, next cursor: #{page.next_cursor.inspect}"
