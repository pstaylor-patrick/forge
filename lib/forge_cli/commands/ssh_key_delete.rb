# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge ssh-key-delete KEY [-S SERVER]: remove an SSH key (name or id).
    # Guarded: the user types the key name.
    class SshKeyDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "ssh-key-delete KEY [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query = CommandSupport.one_arg!(parser, argv, "KEY")
        server = ctx.server(opts[:server])
        org = ctx.org
        key = ctx.ssh_key(server[:id], query)
        label = "#{key[:id]} (#{key[:name]})"
        CommandSupport.write!(
          ctx, command: "ssh-key-delete", request: Endpoints.delete_ssh_key(org, server[:id], key[:id]),
               opts: opts, affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "delete SSH key #{label} on server #{server[:name]}", token: key[:name] },
               summary: ->(_) { "Deleted SSH key #{label} on #{server[:name]}" }
        )
      end
    end
  end
end
