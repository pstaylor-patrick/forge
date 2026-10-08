# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge domain-delete SITE DOMAIN: remove a domain (name or id) from a
    # site. Guarded: the user types the domain name.
    class DomainDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "domain-delete SITE DOMAIN [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query, domain_query = CommandSupport.args!(parser, argv, "SITE", "DOMAIN")
        ref = ctx.site(query, server_query: opts[:server])
        domain = ctx.domain(ref, domain_query)
        org = ctx.org
        label = "#{domain[:id]} (#{domain[:name]})"
        CommandSupport.write!(
          ctx, command: "domain-delete", request: Endpoints.delete_domain(org, ref[:server_id], ref[:site_id], domain[:id]),
               opts: opts, affected: CommandSupport.site_affected(org, ref),
               confirm: { action: "remove domain #{label} from site #{ref[:name]} (id #{ref[:site_id]})",
                          token: domain[:name].to_s },
               summary: ->(_) { "Removed domain #{label} from #{ref[:name]}" }
        )
      end
    end
  end
end
