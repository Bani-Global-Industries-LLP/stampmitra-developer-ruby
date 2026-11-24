# frozen_string_literal: true

module StampMitra
  module Resources
    # Shared validation of the wallet resources. Not part of the public API.
    # @api private
    module WalletSupport
      private

      def check_page_params(limit)
        return unless validate? && !limit.nil? && !(limit.is_a?(Integer) && limit >= 1)

        raise ValidationError.for_field('limit', 'limit must be a positive Integer')
      end

      # The amount the payer wants credited, in rupees, as a JSON number. Fees are never computed here: read them from the response.
      def topup_body(base_amount)
        ok = base_amount.is_a?(Numeric) && !base_amount.is_a?(Complex) && base_amount.to_f.finite? && base_amount.positive?
        raise ValidationError.for_field('baseAmount', 'baseAmount must be a positive number of rupees') if validate? && !ok

        { 'baseAmount' => base_amount.is_a?(Integer) || base_amount.is_a?(Float) ? base_amount : base_amount.to_f }
      end
    end

    # The two e-Stamp wallets (+client.wallets+): +get+ reads both, +stamp_duty+ and +service_fee+ manage one each.
    class Wallets < Base
      # @return [StampDutyWallet] +client.wallets.stamp_duty+
      attr_reader :stamp_duty
      # @return [ServiceFeeWallet] +client.wallets.service_fee+
      attr_reader :service_fee

      # @param transport [Transport]
      # @param options [Hash] +validate_input:+ and +with_response:+
      def initialize(transport, **options)
        super
        @stamp_duty = StampDutyWallet.new(transport, **options)
        @service_fee = ServiceFeeWallet.new(transport, **options)
      end

      # Both wallets in one read (GET /v1/estamp/wallet): the Stamp Duty Wallet, and under +service_fee+ the Service Fee Wallet.
      #
      # @param options [Hash, nil]
      # @return [Models::EstampWallet]
      def get(options: nil)
        api_get('/v1/estamp/wallet', Models::EstampWallet, options: options)
      end
    end

    # The Stamp Duty Wallet (+client.wallets.stamp_duty+).
    class StampDutyWallet < Base
      include WalletSupport

      # Balance (GET /v1/stamp-duty-wallet).
      #
      # @param options [Hash, nil]
      # @return [Models::WalletBalance]
      def get_balance(options: nil)
        api_get('/v1/stamp-duty-wallet', Models::WalletBalance, options: options)
      end

      # Starts a top-up (POST /v1/stamp-duty-wallet/topup). The wallet is credited +base_amount+ in full once the payment
      # succeeds; a processing fee (6%) plus GST (18% on that fee) is added to what the payer pays, and a GST tax invoice
      # for the fee is available from {#list_invoices}. Show the payer +total_charged+ and the fee lines from the response:
      # the rate can change, so never calculate them yourself. NEVER retried automatically (it takes no Idempotency-Key).
      #
      # @param base_amount [Numeric] rupees to add to the wallet, without fee or tax
      # @param options [Hash, nil]
      # @return [Models::StampDutyWalletTopup]
      def topup(base_amount:, options: nil)
        api_post('/v1/stamp-duty-wallet/topup', Models::StampDutyWalletTopup, topup_body(base_amount), options: options,
                                                                                                       idempotent: false, retry_policy: :never)
      end

      # One page of ledger entries (GET /v1/stamp-duty-wallet/transactions).
      #
      # @param limit [Integer, nil] page size
      # @param cursor [String, nil] +next_cursor+ of a previous page
      # @param options [Hash, nil]
      # @return [Models::WalletTransactionsPage]
      def list_transactions(limit: nil, cursor: nil, options: nil)
        check_page_params(limit)
        api_get('/v1/stamp-duty-wallet/transactions', Models::WalletTransactionsPage, query: { limit: limit, cursor: cursor },
                                                                                      options: options)
      end

      # Iterates every ledger entry, following +next_cursor+ lazily.
      # @param filters [Hash] +limit+, +cursor+, +options+
      # @return [Enumerator<Models::WalletTransaction>, nil]
      def each_transaction(**filters, &block)
        each_item(:each_transaction, :each_transaction_page, :list_transactions, filters, &block)
      end

      # Iterates ledger pages.
      # @param filters [Hash] see {#each_transaction}
      # @return [Enumerator<Models::WalletTransactionsPage>, nil]
      def each_transaction_page(**filters, &block)
        each_page_of(:each_transaction_page, :list_transactions, filters, &block)
      end

      # One page of GST tax invoices for top-up fees (GET /v1/stamp-duty-wallet/invoices).
      #
      # @param limit [Integer, nil]
      # @param cursor [String, nil]
      # @param options [Hash, nil]
      # @return [Models::StampDutyWalletInvoicesPage]
      def list_invoices(limit: nil, cursor: nil, options: nil)
        check_page_params(limit)
        api_get('/v1/stamp-duty-wallet/invoices', Models::StampDutyWalletInvoicesPage, query: { limit: limit, cursor: cursor },
                                                                                       options: options)
      end

      # Iterates every invoice, following +next_cursor+ lazily.
      # @param filters [Hash] +limit+, +cursor+, +options+
      # @return [Enumerator<Models::StampDutyWalletInvoice>, nil]
      def each_invoice(**filters, &block)
        each_item(:each_invoice, :each_invoice_page, :list_invoices, filters, &block)
      end

      # Iterates invoice pages.
      # @param filters [Hash] see {#each_invoice}
      # @return [Enumerator<Models::StampDutyWalletInvoicesPage>, nil]
      def each_invoice_page(**filters, &block)
        each_page_of(:each_invoice_page, :list_invoices, filters, &block)
      end

      # One invoice (GET /v1/stamp-duty-wallet/invoices/:id); the +topup_id+ of a top-up is the invoice id.
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::StampDutyWalletInvoice]
      def get_invoice(id, options: nil)
        api_get("/v1/stamp-duty-wallet/invoices/#{seg(id, :id)}", Models::StampDutyWalletInvoice, options: options)
      end
    end

    # The Service Fee Wallet (+client.wallets.service_fee+).
    class ServiceFeeWallet < Base
      include WalletSupport

      # Balance (GET /v1/service-fee-wallet).
      #
      # @param options [Hash, nil]
      # @return [Models::WalletBalance]
      def get_balance(options: nil)
        api_get('/v1/service-fee-wallet', Models::WalletBalance, options: options)
      end

      # Starts a top-up (POST /v1/service-fee-wallet/topup). GST is added on +base_amount+ and the wallet is credited
      # +base_amount+; every amount of the response is a decimal string. NEVER retried automatically.
      #
      # @param base_amount [Numeric] rupees to add to the wallet, without tax
      # @param options [Hash, nil]
      # @return [Models::ServiceFeeWalletTopup]
      def topup(base_amount:, options: nil)
        api_post('/v1/service-fee-wallet/topup', Models::ServiceFeeWalletTopup, topup_body(base_amount), options: options,
                                                                                                         idempotent: false, retry_policy: :never)
      end

      # One page of ledger entries (GET /v1/service-fee-wallet/transactions).
      #
      # @param limit [Integer, nil]
      # @param cursor [String, nil]
      # @param options [Hash, nil]
      # @return [Models::WalletTransactionsPage]
      def list_transactions(limit: nil, cursor: nil, options: nil)
        check_page_params(limit)
        api_get('/v1/service-fee-wallet/transactions', Models::WalletTransactionsPage, query: { limit: limit, cursor: cursor },
                                                                                       options: options)
      end

      # Iterates every ledger entry, following +next_cursor+ lazily.
      # @param filters [Hash] +limit+, +cursor+, +options+
      # @return [Enumerator<Models::WalletTransaction>, nil]
      def each_transaction(**filters, &block)
        each_item(:each_transaction, :each_transaction_page, :list_transactions, filters, &block)
      end

      # Iterates ledger pages.
      # @param filters [Hash] see {#each_transaction}
      # @return [Enumerator<Models::WalletTransactionsPage>, nil]
      def each_transaction_page(**filters, &block)
        each_page_of(:each_transaction_page, :list_transactions, filters, &block)
      end

      # One page of GST invoices (GET /v1/service-fee-wallet/invoices).
      #
      # @param limit [Integer, nil]
      # @param cursor [String, nil]
      # @param options [Hash, nil]
      # @return [Models::WalletInvoicesPage]
      def list_invoices(limit: nil, cursor: nil, options: nil)
        check_page_params(limit)
        api_get('/v1/service-fee-wallet/invoices', Models::WalletInvoicesPage, query: { limit: limit, cursor: cursor }, options: options)
      end

      # Iterates every invoice, following +next_cursor+ lazily.
      # @param filters [Hash] +limit+, +cursor+, +options+
      # @return [Enumerator<Models::WalletInvoice>, nil]
      def each_invoice(**filters, &block)
        each_item(:each_invoice, :each_invoice_page, :list_invoices, filters, &block)
      end

      # Iterates invoice pages.
      # @param filters [Hash] see {#each_invoice}
      # @return [Enumerator<Models::WalletInvoicesPage>, nil]
      def each_invoice_page(**filters, &block)
        each_page_of(:each_invoice_page, :list_invoices, filters, &block)
      end

      # One invoice (GET /v1/service-fee-wallet/invoices/:id).
      #
      # @param id [String]
      # @param options [Hash, nil]
      # @return [Models::WalletInvoice]
      def get_invoice(id, options: nil)
        api_get("/v1/service-fee-wallet/invoices/#{seg(id, :id)}", Models::WalletInvoice, options: options)
      end
    end
  end
end
