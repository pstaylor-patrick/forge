# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge reboot [-S SERVER] [--power-cycle]: reboot (or power-cycle) the
    # server. Guarded: the user types the server name.
    class Reboot
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "reboot [-S SERVER] [--power-cycle] [-d] [-y]",
                                             write: true, destructive: true, server: true) do |o|
          o.on("--power-cycle", "Power-cycle at the provider instead of a clean reboot") { opts[:power_cycle] = true }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        action = opts[:power_cycle] ? "power-cycle" : "reboot"
        server = ctx.server(opts[:server])
        org = ctx.org
        CommandSupport.write!(
          ctx, command: "reboot", request: Endpoints.server_action(org, server[:id], action: action), opts: opts,
               affected: CommandSupport.server_affected(org, server[:id]),
               confirm: { action: "#{action} server #{server[:name]} (id #{server[:id]}); every site on it goes down " \
                                  "until it is back", token: server[:name] },
               summary: ->(_) { "Sent #{action} to server #{server[:name]}" }
        )
      end
    end
  end
end
