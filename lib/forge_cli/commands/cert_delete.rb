# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge cert-delete SITE DOMAIN CERT_ID: remove a certificate from one of
    # the site's domains. Guarded: the user types the domain name.
    class CertDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "cert-delete SITE DOMAIN CERT_ID [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true)
        query, domain_query, cert_id = CommandSupport.args!(parser, argv, "SITE", "DOMAIN", "CERT_ID")
        ref = ctx.site(query, server_query: opts[:server])
        domain = ctx.domain(ref, domain_query)
        cert = ctx.domain_certificate(ref, domain[:id], cert_id)
        org = ctx.org
        label = "#{cert[:id]} (#{cert[:type]})"
        request = Endpoints.delete_certificate(org, ref[:server_id], ref[:site_id], domain[:id], cert[:id])
        CommandSupport.write!(
          ctx, command: "cert-delete", request: request, opts: opts, affected: CommandSupport.site_affected(org, ref),
               confirm: { action: "delete certificate #{label} for domain #{domain[:name]} on site #{ref[:name]}",
                          token: domain[:name].to_s },
               summary: ->(_) { "Deleted certificate #{label} for #{domain[:name]} on #{ref[:name]}" }
        )
      end
    end
  end
end
