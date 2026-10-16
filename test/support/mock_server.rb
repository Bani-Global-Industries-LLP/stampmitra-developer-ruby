# frozen_string_literal: true

require 'net/http'
require 'json'
require 'socket'
require 'uri'

# Locates or starts the spec repository's mock server (scripts/mock-server.mjs).
#
#   MOCK_SERVER_URL=http://127.0.0.1:4010   use a server you started yourself
#   STAMPMITRA_SPEC_DIR=/path/to/stampmitra-developer-openapi   start `node scripts/mock-server.mjs` on a free port
#                                           (defaults to ../stampmitra-developer-openapi next to this repository)
#   CONFORMANCE_REQUIRED=1                  fail instead of skipping when no mock server can be provided (CI)
#
# All control-plane requests ask for "Connection: close", so no keep-alive connection is ever reused.
module MockServer
  ROOT = File.expand_path('../..', __dir__)

  class Unavailable < StandardError; end

  module_function

  def spec_dir
    (ENV.fetch('STAMPMITRA_SPEC_DIR', nil) unless ENV['STAMPMITRA_SPEC_DIR'].to_s.empty?) || File.expand_path('../stampmitra-developer-openapi', ROOT)
  end

  def url
    @url ||= ENV['MOCK_SERVER_URL'].to_s.empty? ? start : ENV['MOCK_SERVER_URL'].chomp('/')
  end

  def start
    script = File.join(spec_dir, 'scripts', 'mock-server.mjs')
    raise Unavailable, "mock server script not found: #{script} (set STAMPMITRA_SPEC_DIR or MOCK_SERVER_URL)" unless File.exist?(script)

    port = TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] }
    pid = Process.spawn(ENV.fetch('NODE', 'node'), script, '--port', port.to_s, '--host', '127.0.0.1', out: File::NULL, err: File::NULL)
    at_exit { Process.kill('TERM', pid) rescue nil } # rubocop:disable Style/RescueModifier
    base = "http://127.0.0.1:#{port}"
    wait_until_healthy(base)
    base
  rescue Errno::ENOENT => e
    raise Unavailable, "cannot start node: #{e.message}"
  end

  def wait_until_healthy(base)
    50.times do
      return if get_json("#{base}/__mock/health")['ok']
    rescue StandardError
      sleep 0.2
    end
    raise Unavailable, "mock server did not become healthy at #{base}"
  end

  def get_json(target)
    JSON.parse(request(:get, target))
  end

  def reset
    request(:post, "#{url}/__mock/reset")
  end

  def recorded
    get_json("#{url}/__mock/requests")
  end

  def request(verb, target)
    uri = URI(target)
    http = Net::HTTP.new(uri.host, uri.port)
    http.max_retries = 0
    http.open_timeout = http.read_timeout = 5
    req = verb == :post ? Net::HTTP::Post.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
    req['Connection'] = 'close'
    if verb == :post
      req['Content-Type'] = 'application/json'
      req.body = '{}'
    end
    http.start { |conn| conn.request(req).body.to_s }
  end
end
