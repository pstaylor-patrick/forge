# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge firewall [-S SERVER]: the server's firewall rules.
    class Firewall
      COLUMNS = %i[id name port type ip_address status].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "firewall [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)
        server_id = ctx.server(opts[:server])[:id]
        formatter.list("firewall", ctx.client.fetch_all(Endpoints.firewall_rules(ctx.org, server_id)), columns: COLUMNS)
      end
    end
  end
end
