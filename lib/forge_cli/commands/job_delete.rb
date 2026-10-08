# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge job-delete JOB [--site SITE] [-S SERVER]: remove a scheduled job
    # (name or id), on the server or on a site. Guarded: the user types the
    # job name, or its id when it has none.
    class JobDelete
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "job-delete JOB [--site SITE] [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true) do |o|
          o.on("--site SITE", "The job is scheduled on this site") { |v| opts[:site] = v }
        end
        query = CommandSupport.one_arg!(parser, argv, "JOB")
        org = ctx.org
        if opts[:site]
          ref = ctx.site(opts[:site], server_query: opts[:server])
          job = ctx.job(ref[:server_id], query, site: ref)
          request = Endpoints.delete_site_job(org, ref[:server_id], ref[:site_id], job[:id])
          affected = CommandSupport.site_affected(org, ref)
          where = "site #{ref[:name]}"
        else
          server = ctx.server(opts[:server])
          job = ctx.job(server[:id], query)
          request = Endpoints.delete_server_job(org, server[:id], job[:id])
          affected = CommandSupport.server_affected(org, server[:id])
          where = "server #{server[:name]}"
        end
        name = job[:name].to_s.strip
        token = name.empty? ? job[:id].to_s : name
        label = "#{job[:id]} (#{name.empty? ? job[:command] : name})"
        CommandSupport.write!(ctx, command: "job-delete", request: request, opts: opts, affected: affected,
                                   confirm: { action: "delete scheduled job #{label} on #{where}", token: token },
                                   summary: ->(_) { "Deleted scheduled job #{label} on #{where}" })
      end
    end
  end
end
