# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge db-users [-S SERVER]: the server's database users.
    class DbUsers
      COLUMNS = %i[id name status created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-users [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)
        server_id = ctx.server(opts[:server])[:id]
        formatter.list("db-users", ctx.client.fetch_all(Endpoints.db_users(ctx.org, server_id)), columns: COLUMNS)
      end
    end
  end
end
