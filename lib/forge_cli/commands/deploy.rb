# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge deploy SITE [-w/--wait] [--timeout SEC]: queue a deployment. With
    # --wait, poll it until it reaches a terminal status; anything but
    # finished (or the timeout) raises DeployFailed (exit 1).
    class Deploy
      DEFAULT_TIMEOUT = 900
      POLL_INTERVAL = 5
      FAILED = %w[failed failed-build cancelled].freeze

      def self.run(argv, ctx:, formatter:, sleeper: ->(seconds) { sleep(seconds) }, clock: method(:monotonic),
                   err: $stderr)
        opts = { wait: false }
        parser = CommandSupport.parser(opts, banner: "deploy SITE [-w|--wait] [--timeout SEC] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("-w", "--wait", "Poll until the deployment finishes (exit 1 if it fails)") { opts[:wait] = true }
          o.on("--timeout SEC", "Give up waiting after SEC seconds (default #{DEFAULT_TIMEOUT})") do |v|
            opts[:timeout] = CommandSupport.count(v, flag: "--timeout")
          end
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        raise Error, "--timeout needs --wait" if opts[:timeout] && !opts[:wait]

        ref = ctx.site(query, server_query: opts[:server])
        org = ctx.org
        affected = CommandSupport.site_affected(org, ref)
        summary = lambda do |result|
          data = result[:data] || {}
          "Deployment #{data[:id]} #{data.dig(:attributes, :status) || 'queued'} for #{ref[:name]}"
        end

        CommandSupport.write!(ctx, command: "deploy", request: Endpoints.deploy(org, ref[:server_id], ref[:site_id]),
                                   opts: opts, affected: affected, summary: summary) do |result|
          next result unless opts[:wait]

          id = result.dig(:data, :id)
          raise Error, "Forge did not return a deployment id; check forge deploys #{ref[:name]}" if id.nil?

          begin
            wait(ctx.client, Endpoints.deployment(org, ref[:server_id], ref[:site_id], id),
                 site_name: ref[:name], id: id, timeout: opts[:timeout] || DEFAULT_TIMEOUT,
                 sleeper: sleeper, clock: clock, err: err)
          rescue DeployFailed => e
            raise DeployFailed.new(e.message, affected: affected)
          end
        end
      end

      # Polls request (the deployment) every interval seconds until its status
      # is terminal. Prints each status change to err. Returns the final body
      # when finished; raises DeployFailed on a failed status or the timeout.
      def self.wait(client, request, site_name:, id:, timeout:, interval: POLL_INTERVAL,
                    sleeper: ->(seconds) { sleep(seconds) }, clock: method(:monotonic), err: $stderr)
        deadline = clock.call + timeout
        last = nil
        loop do
          body = client.fetch(request)
          status = body.dig(:data, :attributes, :status)
          err.puts "deployment #{id}: #{status || 'unknown'}" if status != last
          last = status
          return body if status == "finished"
          raise DeployFailed, failure_message(id, site_name, "ended #{status}") if FAILED.include?(status)

          if clock.call + interval > deadline
            raise DeployFailed, failure_message(id, site_name, "still #{status || 'unknown'} after #{timeout}s")
          end

          sleeper.call(interval)
        end
      end

      def self.failure_message(id, site_name, what)
        "deployment #{id} #{what}; see: forge deploy-log #{site_name} #{id}"
      end

      def self.monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      private_class_method :failure_message, :monotonic
    end
  end
end
