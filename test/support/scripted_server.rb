# frozen_string_literal: true

require 'socket'
require 'json'
require 'openssl'

# A tiny real HTTP/1.1 server on 127.0.0.1 for tests that need genuine sockets (non-JSON bodies, dropped
# connections, hangs, redirects). Every response is sent with "Connection: close", so each request uses a new
# connection and a transparently replayed request would show up as an extra recorded request.
class ScriptedServer
  Request = Struct.new(:verb, :path, :headers, :body)

  attr_reader :requests, :port, :connections

  # steps: Hash { status:, headers:, body: } | :drop (close without responding) | :hang (never respond)
  def initialize(*steps, ssl_context: nil)
    @steps = steps
    @requests = []
    @connections = 0
    @mutex = Mutex.new
    @tcp = TCPServer.new('127.0.0.1', 0)
    @port = @tcp.addr[1]
    @server = ssl_context ? OpenSSL::SSL::SSLServer.new(@tcp, ssl_context) : @tcp
    @threads = []
    @running = true
    @acceptor = Thread.new { accept_loop }
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  def stop
    @running = false
    @tcp.close
    @acceptor.join(1)
    @threads.each(&:kill)
  end

  def json_bodies
    requests.map { |r| r.body.to_s.empty? ? nil : JSON.parse(r.body) }
  end

  def self.run(*steps, **opts)
    server = new(*steps, **opts)
    yield server
  ensure
    server&.stop
  end

  private

  def accept_loop
    while @running
      begin
        socket = @server.accept
      rescue IOError, Errno::EBADF, OpenSSL::SSL::SSLError
        next
      end
      @mutex.synchronize { @connections += 1 }
      @threads << Thread.new(socket) { |s| serve(s) }
    end
  end

  def serve(socket)
    request = read_request(socket)
    return socket.close unless request

    step = @mutex.synchronize do
      @requests << request
      @steps[[@requests.size - 1, @steps.size - 1].min]
    end
    case step
    when :drop then socket.close
    when :hang then sleep
    else respond(socket, step)
    end
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def read_request(socket)
    line = socket.gets
    return nil unless line

    verb, path = line.split
    headers = {}
    while (header = socket.gets) && header != "\r\n"
      name, value = header.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end
    body = headers['content-length'] ? socket.read(headers['content-length'].to_i) : nil
    Request.new(verb, path, headers, body)
  end

  def respond(socket, step)
    step = { status: 200, body: step } unless step.is_a?(Hash) && step.key?(:status)
    body = step[:body]
    text = body.is_a?(String) ? body : JSON.generate(body)
    headers = { 'Content-Type' => 'application/json', 'Content-Length' => text.bytesize.to_s, 'Connection' => 'close' }
    headers.merge!(step[:headers] || {})
    socket.write("HTTP/1.1 #{step[:status]} X\r\n#{headers.map { |k, v| "#{k}: #{v}" }.join("\r\n")}\r\n\r\n#{text}")
    socket.close
  end
end
