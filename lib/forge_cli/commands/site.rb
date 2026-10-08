# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/records"

module ForgeCli
  module Commands
    # forge site SITE: one site's details. SITE is a domain name or id.
    class Site
      FIELDS = %i[id name server_id status url user https web_directory root_directory aliases php_version
                  deployment_status quick_deploy isolated repository zero_downtime_deployments
                  deployment_retention app_type healthcheck_url created_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "site SITE [-S SERVER]", server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        record = ctx.client.fetch(Endpoints.org_site(ctx.org, ref[:site_id]))[:data]
        derive = lambda do |r|
          { server_id: Records.rel_id(r, :server) || ref[:server_id], repository: Records.repository_summary(r) }
        end
        formatter.show("site", record, fields: FIELDS, derive: derive)
      end
    end
  end
end
