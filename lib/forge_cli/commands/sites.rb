# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/records"

module ForgeCli
  module Commands
    # forge sites [-S SERVER]: every site in the org, or on one server.
    class Sites
      COLUMNS = %i[id name server_id php_version deployment_status repository].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "sites [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)

        if opts[:server]
          server_id = ctx.server(opts[:server])[:id]
          records = ctx.client.fetch_all(Endpoints.server_sites(ctx.org, server_id))
          derive = ->(r) { { server_id: server_id, repository: Records.repository_summary(r) } }
        else
          records = ctx.client.fetch_all(Endpoints.org_sites(ctx.org))
          derive = ->(r) { { server_id: Records.rel_id(r, :server), repository: Records.repository_summary(r) } }
        end
        formatter.list("sites", records, columns: COLUMNS, derive: derive)
      end
    end
  end
end
