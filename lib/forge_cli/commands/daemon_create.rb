# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge daemon-create --name NAME --command CMD [--user forge|root]
    #   [--directory DIR] [--processes N] [--site SITE] [--startsecs N]
    #   [--stopwaitsecs N] [--stopsignal SIG] [-S SERVER]
    # Creates a background process. Not guarded.
    class DaemonCreate
      def self.run(argv, ctx:, formatter:)
        opts = { user: "forge", processes: 1 }
        parser = CommandSupport.parser(opts, banner: "daemon-create --name NAME --command CMD [--user forge|root] " \
                                                     "[--directory DIR] [--processes N] [--site SITE] [--startsecs N] " \
                                                     "[--stopwaitsecs N] [--stopsignal SIG] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--name NAME", "Name of the background process") { |v| opts[:name] = v }
          o.on("--command CMD", "Command to run") { |v| opts[:command] = v }
          o.on("--user USER", "forge (default) or root") { |v| opts[:user] = v }
          o.on("--directory DIR", "Working directory") { |v| opts[:directory] = v }
          o.on("--processes N", "Number of processes (default 1)") { |v| opts[:processes] = CommandSupport.count(v, flag: "--processes") }
          o.on("--site SITE", "Associate the process with this site") { |v| opts[:site] = v }
          o.on("--startsecs N", "Seconds the process must stay up to count as started") do |v|
            opts[:startsecs] = CommandSupport.count(v, flag: "--startsecs", min: 0)
          end
          o.on("--stopwaitsecs N", "Seconds to wait for a clean stop") do |v|
            opts[:stopwaitsecs] = CommandSupport.count(v, flag: "--stopwaitsecs", min: 0)
          end
          o.on("--stopsignal SIG", "Signal that stops the process, e.g. SIGTERM") { |v| opts[:stopsignal] = v }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        %i[name command].each do |key|
          raise Error, "--#{key} is required\n#{parser.banner}" if opts[key].to_s.strip.empty?
        end
        CommandSupport.one_of!(opts[:user], Endpoints::DAEMON_USERS, flag: "--user")

        server, site = CommandSupport.server_and_site(ctx, opts)
        org = ctx.org
        request = Endpoints.create_daemon(
          org, server[:id], name: opts[:name], command: opts[:command], user: opts[:user],
                            processes: opts[:processes], directory: opts[:directory], site_id: site && Integer(site[:site_id]),
                            startsecs: opts[:startsecs], stopwaitsecs: opts[:stopwaitsecs], stopsignal: opts[:stopsignal]
        )
        CommandSupport.write!(ctx, command: "daemon-create", request: request, opts: opts,
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Created background process #{[id, "(#{opts[:name]})"].compact.join(' ')} on #{server[:name]}"
                                   })
      end
    end
  end
end
