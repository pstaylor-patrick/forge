# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge ssh-keys [-S SERVER]: the SSH keys installed on the server.
    class SshKeys
      COLUMNS = %i[id name user status created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "ssh-keys [-S SERVER]", server: true)
        CommandSupport.parse!(parser, argv, max_args: 0)
        server_id = ctx.server(opts[:server])[:id]
        formatter.list("ssh-keys", ctx.client.fetch_all(Endpoints.ssh_keys(ctx.org, server_id)), columns: COLUMNS)
      end
    end
  end
end
