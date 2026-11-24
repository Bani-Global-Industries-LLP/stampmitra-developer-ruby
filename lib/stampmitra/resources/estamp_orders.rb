# frozen_string_literal: true

module StampMitra
  module Resources
    # Typed e-Stamp orders (+client.estamp.orders+). Not to be confused with the generic +client.orders+.
    #
    # One order covers exactly one state and up to 5000 stamp lines (see {EstampStampLine}). Order creation spends
    # money: the +Idempotency-Key+ is REQUIRED by the API, so the gem generates one when you do not pass
    # +options: { idempotency_key: }+ and reuses it on every automatic retry.
    class EstampOrders < Base
      # Largest accepted document upload, in bytes (10 MB).
      MAX_DOCUMENT_BYTES = 10 * 1024 * 1024
      # File extensions accepted for a PAN card document, with the content type sent for each.
      DOCUMENT_TYPES = { '.pdf' => 'application/pdf', '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png' }.freeze
      MAGIC = { 'application/pdf' => '%PDF-'.b, 'image/jpeg' => "\xFF\xD8\xFF".b, 'image/png' => "\x89PNG".b }.freeze
      private_constant :MAGIC

      # Dry-runs an order: nothing is created and nothing is billed (POST /v1/estamp/orders/validate). It takes no
      # Idempotency-Key and is safe to retry, so it is retried automatically on 429 / 5xx / connection errors.
      #
      # @param stamps [Array<EstampStampLine, Hash>] one to 5000 lines, all in one state
      # @param reference [String, nil] your own reference for the whole order
      # @param options [Hash, nil]
      # @return [Models::EstampValidateResult] check +#valid?+-style fields: +valid+, +errors+, +warnings+, +quote+
      def validate(stamps:, reference: nil, options: nil)
        api_post('/v1/estamp/orders/validate', Models::EstampValidateResult, order_body(stamps, reference), options: options,
                                                                                                            idempotent: false, retry_policy: :safe)
      end

      # Creates an order (POST /v1/estamp/orders). Debits the Stamp Duty Wallet and the Service Fee Wallet. A 402 carries
      # +error.wallet+ ("STAMP_DUTY" or "SERVICE_FEE"); a 400 lists every finding in +error.errors+.
      #
      # @param stamps [Array<EstampStampLine, Hash>] one to 5000 lines, all in one state
      # @param reference [String, nil] your own reference for the whole order
      # @param options [Hash, nil] +idempotency_key:+ replaces the generated key (derive it from something stable you own)
      # @return [Models::EstampOrder]
      def create(stamps:, reference: nil, options: nil)
        api_post('/v1/estamp/orders', Models::EstampOrder, order_body(stamps, reference), options: options)
      end

      # One page of your orders (GET /v1/estamp/orders).
      #
      # @param page [Integer, nil] page number (default 1)
      # @param limit [Integer, nil] page size, 1-100 (default 20)
      # @param cursor [String, nil] +next_cursor+ of a previous page
      # @param options [Hash, nil]
      # @return [Models::EstampOrderList] +#items+ and +#next_cursor+
      def list(page: nil, limit: nil, cursor: nil, options: nil)
        if validate?
          raise ValidationError.for_field('page', 'page must be an Integer of at least 1') unless page.nil? || (page.is_a?(Integer) && page >= 1)
          unless limit.nil? || (limit.is_a?(Integer) && limit.between?(1, 100))
            raise ValidationError.for_field('limit', 'limit must be an Integer between 1 and 100')
          end
        end
        api_get('/v1/estamp/orders', Models::EstampOrderList, query: { page: page, limit: limit, cursor: cursor }, options: options)
      end

      # Iterates every order, following +next_cursor+ lazily. Returns an Enumerator without a block.
      #
      # @param filters [Hash] +limit+, +cursor+ and +options+ as for {#list}
      # @yieldparam order [Models::EstampOrder]
      # @return [Enumerator<Models::EstampOrder>, nil]
      def each(**filters, &block)
        each_item(:each, :each_page, :list, filters, &block)
      end

      # Iterates pages ({Models::EstampOrderList}) instead of orders.
      #
      # @param filters [Hash] see {#each}
      # @yieldparam page [Models::EstampOrderList]
      # @return [Enumerator<Models::EstampOrderList>, nil]
      def each_page(**filters, &block)
        each_page_of(:each_page, :list, filters, &block)
      end

      # Fetches an order (GET /v1/estamp/orders/:id).
      #
      # @param id [String] the order +id+ (for example "estord_...")
      # @param options [Hash, nil]
      # @return [Models::EstampOrder]
      def get(id, options: nil)
        api_get("/v1/estamp/orders/#{seg(id, :id)}", Models::EstampOrder, options: options)
      end

      # Cancels an order (POST /v1/estamp/orders/:id/cancel). NEVER retried automatically.
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampOrder]
      def cancel(id, options: nil)
        api_post("/v1/estamp/orders/#{seg(id, :id)}/cancel", Models::EstampOrder, nil, options: options, idempotent: false,
                                                                                       retry_policy: :never)
      end

      # A small CSV for reconciliation (GET /v1/estamp/orders/:id/export).
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampOrderExport] +#filename+ and +#csv+
      def export(id, options: nil)
        api_get("/v1/estamp/orders/#{seg(id, :id)}/export", Models::EstampOrderExport, options: options)
      end

      # The stamps of an order (GET /v1/estamp/orders/:id/stamps).
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampStampList] +#items+, +#count+, +#next_cursor+
      def list_stamps(id, options: nil)
        api_get("/v1/estamp/orders/#{seg(id, :id)}/stamps", Models::EstampStampList, options: options)
      end

      # Uploads the payer's PAN card (POST /v1/estamp/orders/:orderId/documents, multipart/form-data). The PAN card is
      # advisory: it never blocks an order. An Idempotency-Key is generated (and reused across retries, re-sending the
      # whole body) unless you pass one.
      #
      # @param order_id [String]
      # @param file [String, Pathname, #read] a path, or an IO / StringIO holding a PDF, JPEG or PNG of at most 10 MB
      # @param type [String, Symbol, nil] only "pan_card" is accepted; the part is sent only when you pass it
      # @param filename [String, nil] file name to send (defaults to the path's basename; required for an IO without a path)
      # @param content_type [String, nil] defaults to the one implied by the file extension, else sniffed from the first bytes
      # @param options [Hash, nil]
      # @return [Models::EstampDocument]
      def upload_document(order_id, file:, type: nil, filename: nil, content_type: nil, options: nil)
        id = seg(order_id, :order_id)
        type = type&.to_s
        raise ValidationError.for_field('type', "type must be 'pan_card'") unless type.nil? || type == 'pan_card' || !validate?

        parts = [file_part(file, filename, content_type)]
        parts << Multipart::Part.new('type', type) if type
        api_post("/v1/estamp/orders/#{id}/documents", Models::EstampDocument, nil, options: options, multipart: parts)
      end

      private

      def order_body(stamps, reference)
        lines = EstampOrderInput.lines(stamps)
        EstampOrderInput.check!(lines) if validate?
        raise ValidationError.for_field('reference', 'reference must be a String') if validate? && !reference.nil? && !reference.is_a?(String)

        { 'reference' => reference, 'stamps' => lines }
      end

      def file_part(file, filename, content_type)
        data, name = read_file(file, filename)
        type = content_type || sniff_type(name, data)
        check_document!(data, type) if validate?
        Multipart::Part.new('file', data, name, type || 'application/octet-stream')
      end

      def read_file(file, filename)
        return read_path(file.to_s, filename) if file.is_a?(String) || (defined?(Pathname) && file.is_a?(Pathname))
        raise ValidationError.for_field('file', 'file must be a path or an IO') unless file.respond_to?(:read)

        name = filename || (File.basename(file.path) if file.respond_to?(:path) && file.path)
        raise ValidationError.for_field('filename', 'filename is required when file is an IO without a path') if name.nil?

        file.binmode if file.respond_to?(:binmode)
        [file.read.to_s.b, name]
      end

      def read_path(path, filename)
        raise ValidationError.for_field('file', "file not found: #{File.basename(path)}") unless File.file?(path)

        check_size!(File.size(path)) if validate?
        [File.binread(path), filename || File.basename(path)]
      end

      def sniff_type(name, data)
        DOCUMENT_TYPES[File.extname(name.to_s).downcase] || MAGIC.find { |_type, magic| data.b.start_with?(magic) }&.first
      end

      def check_document!(data, type)
        raise ValidationError.for_field('file', 'file is empty') if data.empty?

        check_size!(data.bytesize)
        return if MAGIC.key?(type)

        raise ValidationError.new('file must be a PDF, JPEG or PNG', code: 'UNSUPPORTED_FILE_TYPE', field: 'file')
      end

      def check_size!(bytes)
        return if bytes <= MAX_DOCUMENT_BYTES

        raise ValidationError.new('file is larger than 10 MB', code: 'FILE_TOO_LARGE', field: 'file')
      end
    end

    # Stamps of an e-Stamp order (+client.estamp.stamps+).
    class EstampStamps < Base
      # Fetches a stamp (GET /v1/estamp/stamps/:stampId). +pan_card.status+ shows the asynchronous PAN card check.
      #
      # @param stamp_id [String] e.g. "eststamp_..."
      # @param options [Hash, nil]
      # @return [Models::EstampStamp]
      def get(stamp_id, options: nil)
        api_get("/v1/estamp/stamps/#{seg(stamp_id, :stamp_id)}", Models::EstampStamp, options: options)
      end

      # Cancels a stamp (POST /v1/estamp/stamps/:stampId/cancel). NEVER retried automatically.
      #
      # @param stamp_id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampStamp]
      def cancel(stamp_id, options: nil)
        api_post("/v1/estamp/stamps/#{seg(stamp_id, :stamp_id)}/cancel", Models::EstampStamp, nil, options: options, idempotent: false,
                                                                                                   retry_policy: :never)
      end

      # Replaces a stamp (POST /v1/estamp/stamps/:stampId/replace). NEVER retried automatically.
      #
      # @param stamp_id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampStamp]
      def replace(stamp_id, options: nil)
        api_post("/v1/estamp/stamps/#{seg(stamp_id, :stamp_id)}/replace", Models::EstampStamp, nil, options: options, idempotent: false,
                                                                                                    retry_policy: :never)
      end

      # Links a PAN card image by +https://+ URL (POST /v1/estamp/stamps/:stampId/pan-card). The API answers 202 Accepted
      # and checks the card afterwards: poll {#get} (+pan_card.status+). NEVER retried automatically.
      #
      # @param stamp_id [String]
      # @param pan_card_image [String] an +https://+ link (max 2048 characters), downloadable without a login
      # @param options [Hash, nil]
      # @return [Models::EstampPanCardResult] +pan_card.status+ is PROCESSING
      def set_pan_card(stamp_id, pan_card_image:, options: nil)
        if validate? && !(pan_card_image.is_a?(String) && pan_card_image.start_with?('https://') && pan_card_image.length <= 2048)
          raise ValidationError.new('panCardImage must be an https:// link of at most 2048 characters', code: 'HTTPS_URL_REQUIRED',
                                                                                                        field: 'panCardImage')
        end
        api_post("/v1/estamp/stamps/#{seg(stamp_id, :stamp_id)}/pan-card", Models::EstampPanCardResult,
                 { 'panCardImage' => pan_card_image }, options: options, idempotent: false, retry_policy: :never)
      end

      # Delivery status and certificate data of a stamp (GET /v1/estamp/stamps/:stampId/certificate). Always HTTP 200:
      # check +available+ / +status+.
      #
      # @param stamp_id [String]
      # @param options [Hash, nil]
      # @return [Models::EstampCertificate]
      def get_certificate(stamp_id, options: nil)
        api_get("/v1/estamp/stamps/#{seg(stamp_id, :stamp_id)}/certificate", Models::EstampCertificate, options: options)
      end
    end
  end
end
