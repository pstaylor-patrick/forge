# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge job-output JOB [-S SERVER] [--site SITE]: a scheduled job's latest
    # output. JOB is a job name or id.
    class JobOutput
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "job-output JOB [-S SERVER] [--site SITE]", server: true) do |o|
          o.on("--site SITE", "The job is scheduled on this site") { |v| opts[:site] = v }
        end
        query = CommandSupport.one_arg!(parser, argv, "JOB")
        if opts[:site]
          ref = ctx.site(opts[:site], server_query: opts[:server])
          job = ctx.job(ref[:server_id], query, site: ref)
          request = Endpoints.site_job_output(ctx.org, ref[:server_id], ref[:site_id], job[:id])
        else
          server_id = ctx.server(opts[:server])[:id]
          job = ctx.job(server_id, query)
          request = Endpoints.server_job_output(ctx.org, server_id, job[:id])
        end
        body = ctx.client.fetch(request)
        formatter.text("job-output", (body.dig(:data, :attributes, :output) || body[:raw]).to_s,
                       meta: { job_id: job[:id], name: job[:name] })
      end
    end
  end
end
