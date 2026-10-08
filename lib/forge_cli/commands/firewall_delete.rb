# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge firewall-delete RULE [-S SERVER]: remove a firewall rule (name or
    # id). Guarded: the user types the rule name.
    class FirewallDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "firewall-delete RULE [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query = CommandSupport.one_arg!(parser, argv, "RULE")
        server = ctx.server(opts[:server])
        org = ctx.org
        rule = ctx.firewall_rule(server[:id], query)
        label = "#{rule[:id]} (#{rule[:name]})"
        CommandSupport.write!(
          ctx, command: "firewall-delete", request: Endpoints.delete_firewall_rule(org, server[:id], rule[:id]),
               opts: opts, affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "delete firewall rule #{label} on server #{server[:name]}", token: rule[:name] },
               summary: ->(_) { "Deleted firewall rule #{label} on #{server[:name]}" }
        )
      end
    end
  end
end
