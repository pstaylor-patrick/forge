# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge logs SITE [--type TYPE] [--tail N]: the last N lines of a site log.
    class Logs
      DEFAULT_TAIL = 200

      def self.run(argv, ctx:, formatter:)
        opts = { type: "application", tail: DEFAULT_TAIL }
        types = Endpoints::SITE_LOG_TYPES
        parser = CommandSupport.parser(opts, banner: "logs SITE [--type #{types.join('|')}] [--tail N] [-S SERVER]",
                                             server: true) do |o|
          o.on("--type TYPE", "Log to read (default application)") { |v| opts[:type] = v }
          o.on("--tail N", "Last N lines (default #{DEFAULT_TAIL}; 0 = all)") do |v|
            opts[:tail] = CommandSupport.count(v, flag: "--tail", min: 0)
          end
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        raise Error, "--type must be one of #{types.join(', ')}, got '#{opts[:type]}'" unless types.include?(opts[:type])

        ref = ctx.site(query, server_query: opts[:server])
        body = ctx.client.fetch(Endpoints.site_log(ctx.org, ref[:server_id], ref[:site_id], opts[:type]))
        content = CommandSupport.tail(body.dig(:data, :attributes, :content) || body[:raw], opts[:tail])
        formatter.text("logs", content, meta: { site: ref[:name], type: opts[:type], log: body.dig(:meta, :log) })
      end
    end
  end
end
