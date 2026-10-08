# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge domain-create SITE DOMAIN [--www from-www|to-www|none] [--wildcard]
    # Adds a domain (alias) to a site. The API requires all three body keys,
    # so www_redirect_type defaults to none and allow_wildcard_subdomains is
    # always sent. Not guarded.
    class DomainCreate
      DEFAULT_WWW = "none"

      def self.run(argv, ctx:, formatter:)
        opts = { www: DEFAULT_WWW, wildcard: false }
        parser = CommandSupport.parser(opts, banner: "domain-create SITE DOMAIN [--www from-www|to-www|none] " \
                                                     "[--wildcard] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--www TYPE", "www redirect (default #{DEFAULT_WWW}): #{Endpoints::WWW_REDIRECT_TYPES.join(', ')}") do |v|
            opts[:www] = v
          end
          o.on("--wildcard", "Answer on every subdomain too") { opts[:wildcard] = true }
        end
        query, name = CommandSupport.args!(parser, argv, "SITE", "DOMAIN")
        domain = CommandSupport.hostname!(name, "DOMAIN")
        CommandSupport.one_of!(opts[:www], Endpoints::WWW_REDIRECT_TYPES, flag: "--www")

        ref = ctx.site(query, server_query: opts[:server])
        org = ctx.org
        request = Endpoints.create_domain(org, ref[:server_id], ref[:site_id], name: domain,
                                                                             www_redirect_type: opts[:www],
                                                                             allow_wildcard_subdomains: opts[:wildcard])
        CommandSupport.write!(ctx, command: "domain-create", request: request, opts: opts,
                                   affected: CommandSupport.site_affected(org, ref),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Added domain #{[id, "(#{domain})"].compact.join(' ')} to #{ref[:name]}"
                                   })
      end
    end
  end
end
