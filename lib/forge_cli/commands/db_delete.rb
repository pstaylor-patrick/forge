# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge db-delete DB [-S SERVER]: drop a database schema (name or id).
    # Guarded: the user types the database name.
    class DbDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-delete DB [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query = CommandSupport.one_arg!(parser, argv, "DB")
        server = ctx.server(opts[:server])
        org = ctx.org
        schema = ctx.schema(server[:id], query)
        label = "#{schema[:id]} (#{schema[:name]})"
        CommandSupport.write!(
          ctx, command: "db-delete", request: Endpoints.delete_schema(org, server[:id], schema[:id]),
               opts: opts, affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "drop database #{label} and all its data on server #{server[:name]}",
                          token: schema[:name].to_s },
               summary: ->(_) { "Deleted database #{label} on #{server[:name]}" }
        )
      end
    end
  end
end
