# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge site-delete SITE [-S SERVER]: delete a site from its server.
    # Guarded: the user types the site name. Opens the server afterwards,
    # since the site page is gone.
    class SiteDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "site-delete SITE [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        server = ctx.server(ref[:server_id].to_s)
        org = ctx.org
        label = "#{ref[:site_id]} (#{ref[:name]})"
        CommandSupport.write!(
          ctx, command: "site-delete", request: Endpoints.delete_site(org, ref[:server_id], ref[:site_id]),
               opts: opts, affected: CommandSupport.server_affected(org, ref[:server_id]),
               confirm: { action: "delete site #{label} and its files on server #{server[:name]} (id #{server[:id]})",
                          token: ref[:name].to_s },
               summary: ->(_) { "Deleted site #{label} on #{server[:name]}" }
        )
      end
    end
  end
end
