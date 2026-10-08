# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge jobs [-S SERVER] [--site SITE]: scheduled jobs on the server, or
    # on one site.
    class Jobs
      COLUMNS = %i[id name command user frequency cron next_run_time status].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "jobs [-S SERVER] [--site SITE]", server: true) do |o|
          o.on("--site SITE", "Jobs scheduled on this site instead of the server") { |v| opts[:site] = v }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        request =
          if opts[:site]
            ref = ctx.site(opts[:site], server_query: opts[:server])
            Endpoints.site_jobs(ctx.org, ref[:server_id], ref[:site_id])
          else
            Endpoints.server_jobs(ctx.org, ctx.server(opts[:server])[:id])
          end
        formatter.list("jobs", ctx.client.fetch_all(request), columns: COLUMNS)
      end
    end
  end
end
