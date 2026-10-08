# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge dbs [-S SERVER]: the server's database schemas.
    class Dbs
      COLUMNS = %i[id name status created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "dbs [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)
        server_id = ctx.server(opts[:server])[:id]
        formatter.list("dbs", ctx.client.fetch_all(Endpoints.schemas(ctx.org, server_id)), columns: COLUMNS)
      end
    end
  end
end
