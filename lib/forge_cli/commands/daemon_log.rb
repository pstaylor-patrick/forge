# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge daemon-log DAEMON_ID [-S SERVER]: a background process's log.
    class DaemonLog
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "daemon-log DAEMON_ID [-S SERVER]", server: true)
        id = CommandSupport.one_arg!(parser, argv, "DAEMON_ID")
        raise Error, "DAEMON_ID must be a numeric id (see forge daemons), got '#{id}'" unless id.match?(/\A\d+\z/)

        server_id = ctx.server(opts[:server])[:id]
        body = ctx.client.fetch(Endpoints.daemon_log(ctx.org, server_id, id))
        formatter.text("daemon-log", (body.dig(:data, :attributes, :content) || body[:raw]).to_s, meta: { daemon_id: id })
      end
    end
  end
end
