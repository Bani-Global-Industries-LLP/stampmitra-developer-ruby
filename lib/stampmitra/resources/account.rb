# frozen_string_literal: true

module StampMitra
  module Resources
    # Account-level reads (+client.account+).
    class Account < Base
      # Prepaid balance, low-balance state and estimated calls remaining (GET /v1/account/balance).
      #
      # @param options [Hash, nil]
      # @return [Models::AccountBalance]
      def balance(options: nil)
        api_get('/v1/account/balance', Models::AccountBalance, options: options)
      end

      # Usage of the current month, the previous month and today, with your limits (GET /v1/account/usage).
      #
      # @param options [Hash, nil]
      # @return [Models::AccountUsage]
      def usage(options: nil)
        api_get('/v1/account/usage', Models::AccountUsage, options: options)
      end
    end
  end
end
