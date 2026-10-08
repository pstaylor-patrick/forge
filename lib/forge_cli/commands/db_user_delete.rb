# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge db-user-delete USER [-S SERVER]: remove a database user (name or
    # id). Guarded: the user types the database user's name.
    class DbUserDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-user-delete USER [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query = CommandSupport.one_arg!(parser, argv, "USER")
        server = ctx.server(opts[:server])
        org = ctx.org
        user = ctx.db_user(server[:id], query)
        label = "#{user[:id]} (#{user[:name]})"
        CommandSupport.write!(
          ctx, command: "db-user-delete", request: Endpoints.delete_db_user(org, server[:id], user[:id]),
               opts: opts, affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "delete database user #{label} on server #{server[:name]}", token: user[:name].to_s },
               summary: ->(_) { "Deleted database user #{label} on #{server[:name]}" }
        )
      end
    end
  end
end
