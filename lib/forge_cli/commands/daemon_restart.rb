# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge daemon-restart DAEMON_ID [-S SERVER]: restart a background process.
    # Not guarded: it comes back by itself.
    class DaemonRestart
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "daemon-restart DAEMON_ID [-S SERVER] [-d]", write: true, server: true)
        id = CommandSupport.one_arg!(parser, argv, "DAEMON_ID")
        server = ctx.server(opts[:server])
        org = ctx.org
        daemon = ctx.daemon(server[:id], id)
        CommandSupport.write!(
          ctx, command: "daemon-restart", request: Endpoints.daemon_action(org, server[:id], daemon[:id], action: "restart"),
               opts: opts, affected: CommandSupport.server_affected(org, server[:id]),
               summary: ->(_) { "Restarting background process #{daemon[:id]} (#{daemon[:command]}) on #{server[:name]}" }
        )
      end
    end
  end
end
