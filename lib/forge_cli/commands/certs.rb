# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge certs SITE: the site's SSL certificates.
    class Certs
      COLUMNS = %i[id type status active request_status key_type created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "certs SITE [-S SERVER]", server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        # Not paginated: one response carries every certificate.
        records = Array(ctx.client.fetch(Endpoints.site_certificates(ctx.org, ref[:server_id], ref[:site_id]))[:data])
        formatter.list("certs", records, columns: COLUMNS)
      end
    end
  end
end
