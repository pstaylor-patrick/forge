# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge server [SERVER]: one server's details. SERVER is a name or id;
    # default FORGE_SERVER, else the org's only server.
    class Server
      FIELDS = %i[id name slug type ubuntu_version provider region size php_version database_type
                  ip_address private_ip_address connection_status is_ready created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "server [SERVER] [-S SERVER]", server: true)
        query = CommandSupport.parse!(parser, argv, max_args: 1).first || opts[:server]
        server = ctx.server(query)
        body = ctx.client.fetch(Endpoints.server(ctx.org, server[:id]))
        formatter.show("server", body[:data], fields: FIELDS)
      end
    end
  end
end
