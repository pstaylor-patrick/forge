# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge events [-S SERVER] [-n N]: recent org events, newest first, or one
    # server's events with -S.
    class Events
      COLUMNS = %i[id description ran_as created_at].freeze
      DEFAULT_COUNT = 20
      MAX_COUNT = 100

      def self.run(argv, ctx:, formatter:)
        opts = { count: DEFAULT_COUNT }
        parser = CommandSupport.parser(opts, banner: "events [-S SERVER] [-n N]", server: true) do |o|
          o.on("-n", "--limit N", "How many (default #{DEFAULT_COUNT}, max #{MAX_COUNT})") do |v|
            opts[:count] = CommandSupport.count(v, flag: "-n", max: MAX_COUNT)
          end
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        request =
          if opts[:server]
            Endpoints.server_events(ctx.org, ctx.server(opts[:server])[:id], size: opts[:count])
          else
            Endpoints.org_events(ctx.org, size: opts[:count])
          end
        records = Array(ctx.client.fetch(request)[:data]).first(opts[:count])
        formatter.list("events", records, columns: COLUMNS)
      end
    end
  end
end
