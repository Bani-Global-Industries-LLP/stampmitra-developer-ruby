# frozen_string_literal: true

require 'securerandom'

module StampMitra
  # Builds a multipart/form-data body (RFC 7578) from plain parts. Standard library only.
  # @api private
  module Multipart
    # One part: a text field (+filename+ nil) or a file.
    Part = Struct.new(:name, :data, :filename, :content_type)

    module_function

    # @param parts [Array<Part>]
    # @return [Array(String, String)] the Content-Type header value (with boundary) and the binary body
    def build(parts)
      boundary = "StampMitraRubyBoundary#{SecureRandom.hex(16)}"
      body = parts.each_with_object(+''.b) do |part, out|
        out << "--#{boundary}\r\n".b << headers(part).b << "\r\n\r\n".b << part.data.to_s.b << "\r\n".b
      end
      body << "--#{boundary}--\r\n".b
      ["multipart/form-data; boundary=#{boundary}", body]
    end

    # @api private
    def headers(part)
      disposition = "Content-Disposition: form-data; name=\"#{escape(part.name)}\""
      disposition += "; filename=\"#{escape(part.filename)}\"" if part.filename
      part.content_type ? "#{disposition}\r\nContent-Type: #{part.content_type}" : disposition
    end

    # Quotes, CR and LF cannot appear raw inside a quoted parameter (WHATWG form-data encoding).
    # @api private
    def escape(text)
      text.to_s.gsub('"', '%22').gsub("\r", '%0D').gsub("\n", '%0A')
    end
  end
end
