# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge daemons [-S SERVER]: the server's background processes.
    class Daemons
      COLUMNS = %i[id command user directory processes status].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "daemons [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)
        server_id = ctx.server(opts[:server])[:id]
        formatter.list("daemons", ctx.client.fetch_all(Endpoints.daemons(ctx.org, server_id)), columns: COLUMNS)
      end
    end
  end
end
