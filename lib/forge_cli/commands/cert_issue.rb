# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge cert-issue SITE DOMAIN [--verification http-01|dns-01] [--key-type ecdsa|rsa]
    # Requests a Let's Encrypt certificate for one of the site's domains (name
    # or id). Let's Encrypt only. Not guarded: it removes nothing.
    class CertIssue
      DEFAULT_VERIFICATION = "http-01"
      DEFAULT_KEY_TYPE = "ecdsa"

      def self.run(argv, ctx:, formatter:)
        opts = { verification: DEFAULT_VERIFICATION, key_type: DEFAULT_KEY_TYPE }
        parser = CommandSupport.parser(opts, banner: "cert-issue SITE DOMAIN [--verification http-01|dns-01] " \
                                                     "[--key-type ecdsa|rsa] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--verification METHOD", "Let's Encrypt challenge (default #{DEFAULT_VERIFICATION}): " \
                                        "#{Endpoints::CERT_VERIFICATION_METHODS.join(', ')}") { |v| opts[:verification] = v }
          o.on("--key-type TYPE", "Key type (default #{DEFAULT_KEY_TYPE}): " \
                                  "#{Endpoints::CERT_KEY_TYPES.join(', ')}") { |v| opts[:key_type] = v }
        end
        query, domain_query = CommandSupport.args!(parser, argv, "SITE", "DOMAIN")
        CommandSupport.one_of!(opts[:verification], Endpoints::CERT_VERIFICATION_METHODS, flag: "--verification")
        CommandSupport.one_of!(opts[:key_type], Endpoints::CERT_KEY_TYPES, flag: "--key-type")

        ref = ctx.site(query, server_query: opts[:server])
        domain = ctx.domain(ref, domain_query)
        org = ctx.org
        request = Endpoints.issue_certificate(org, ref[:server_id], ref[:site_id], domain[:id],
                                              verification_method: opts[:verification], key_type: opts[:key_type])
        CommandSupport.write!(ctx, command: "cert-issue", request: request, opts: opts,
                                   affected: CommandSupport.site_affected(org, ref),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Requested Let's Encrypt certificate #{[id, "for #{domain[:name]}"].compact.join(' ')} " \
                                       "on #{ref[:name]}"
                                   })
      end
    end
  end
end
