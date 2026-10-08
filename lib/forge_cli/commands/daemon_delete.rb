# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge daemon-delete DAEMON_ID [-S SERVER]: remove a background process.
    # Guarded: daemons have no name, so the user types the id.
    class DaemonDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "daemon-delete DAEMON_ID [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        id = CommandSupport.one_arg!(parser, argv, "DAEMON_ID")
        server = ctx.server(opts[:server])
        org = ctx.org
        daemon = ctx.daemon(server[:id], id)
        CommandSupport.write!(
          ctx, command: "daemon-delete", request: Endpoints.delete_daemon(org, server[:id], daemon[:id]), opts: opts,
               affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "delete background process #{daemon[:id]} (#{daemon[:command]}) on server #{server[:name]}",
                          token: daemon[:id].to_s },
               summary: ->(_) { "Deleted background process #{daemon[:id]} (#{daemon[:command]}) on #{server[:name]}" }
        )
      end
    end
  end
end
