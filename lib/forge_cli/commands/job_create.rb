# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge job-create --command CMD --frequency F [--cron EXPR] [--name NAME]
    #   [--user USER] [--heartbeat] [--site SITE] [-S SERVER]
    # Schedules a job on the server, or on a site with --site. --cron is
    # required when F is custom and rejected otherwise. Not guarded.
    class JobCreate
      def self.run(argv, ctx:, formatter:)
        opts = { user: "forge" }
        parser = CommandSupport.parser(opts, banner: "job-create --command CMD --frequency F [--cron EXPR] [--name NAME] " \
                                                     "[--user USER] [--heartbeat] [--site SITE] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--command CMD", "Command to run") { |v| opts[:command] = v }
          o.on("--frequency F", "One of #{Endpoints::JOB_FREQUENCIES.join(', ')}") { |v| opts[:frequency] = v }
          o.on("--cron EXPR", "Cron expression; required (only) with --frequency custom") { |v| opts[:cron] = v }
          o.on("--name NAME", "Job name") { |v| opts[:name] = v }
          o.on("--user USER", "User to run as (default forge)") { |v| opts[:user] = v }
          o.on("--heartbeat", "Create a heartbeat for the job") { opts[:heartbeat] = true }
          o.on("--site SITE", "Schedule the job on this site instead of the server") { |v| opts[:site] = v }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        validate!(opts, parser)

        org = ctx.org
        attrs = { command: opts[:command], user: opts[:user], frequency: opts[:frequency], name: opts[:name],
                  cron: opts[:cron], heartbeat: opts[:heartbeat] }
        if opts[:site]
          ref = ctx.site(opts[:site], server_query: opts[:server])
          request = Endpoints.create_site_job(org, ref[:server_id], ref[:site_id], **attrs)
          affected = CommandSupport.site_affected(org, ref)
          where = ref[:name]
        else
          server = ctx.server(opts[:server])
          request = Endpoints.create_server_job(org, server[:id], **attrs)
          affected = CommandSupport.server_affected(org, server[:id])
          where = server[:name]
        end
        CommandSupport.write!(ctx, command: "job-create", request: request, opts: opts, affected: affected,
                                   summary: lambda { |result|
                                     words = ["Scheduled job", result.dig(:data, :id), opts[:name],
                                              "(#{opts[:frequency]}) on #{where}"]
                                     words.compact.join(" ")
                                   })
      end

      # Checked before any request is made.
      def self.validate!(opts, parser)
        raise Error, "--command is required\n#{parser.banner}" if opts[:command].to_s.strip.empty?
        raise Error, "--frequency is required\n#{parser.banner}" if opts[:frequency].to_s.strip.empty?

        CommandSupport.one_of!(opts[:frequency], Endpoints::JOB_FREQUENCIES, flag: "--frequency")
        custom = opts[:frequency] == "custom"
        raise Error, "--frequency custom needs --cron EXPR, e.g. --cron '0 * * * *'" if custom && opts[:cron].to_s.strip.empty?
        raise Error, "--cron only applies with --frequency custom" if !custom && opts[:cron]
        raise Error, "--user must not be empty" if opts[:user].to_s.strip.empty?
      end

      private_class_method :validate!
    end
  end
end
