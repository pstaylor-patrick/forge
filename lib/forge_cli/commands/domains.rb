# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge domains SITE: the site's domains (primary and aliases).
    class Domains
      COLUMNS = %i[id name type status www_redirect_type allow_wildcard_subdomains].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "domains SITE [-S SERVER]", server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        records = ctx.client.fetch_all(Endpoints.domains(ctx.org, ref[:server_id], ref[:site_id]))
        formatter.list("domains", records, columns: COLUMNS)
      end
    end
  end
end
