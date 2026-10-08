# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge server-log KEY [-S SERVER] [--tail N]: the last N lines of a server
    # log. KEY is passed through unchanged.
    class ServerLog
      DEFAULT_TAIL = 200
      # Observed live; the API documents {key} as a free string.
      KNOWN_KEYS = ["nginx-access", "nginx-error", "php-8.4", "redis-server", "database-mysql"].freeze

      def self.run(argv, ctx:, formatter:)
        opts = { tail: DEFAULT_TAIL }
        parser = CommandSupport.parser(opts, banner: "server-log KEY [-S SERVER] [--tail N]", server: true) do |o|
          o.on("--tail N", "Last N lines (default #{DEFAULT_TAIL}; 0 = all)") do |v|
            opts[:tail] = CommandSupport.count(v, flag: "--tail", min: 0)
          end
        end
        key = CommandSupport.one_arg!(parser, argv, "KEY")
        server_id = ctx.server(opts[:server])[:id]
        body = begin
          ctx.client.fetch(Endpoints.server_log(ctx.org, server_id, key))
        rescue NotFoundError
          raise NotFoundError, "no server log '#{key}' (keys seen on Forge servers: #{KNOWN_KEYS.join(', ')}; " \
                               "the php and database keys follow the installed versions)"
        end
        content = CommandSupport.tail(body.dig(:data, :attributes, :content) || body[:raw], opts[:tail])
        formatter.text("server-log", content, meta: { key: key, log: body.dig(:meta, :log) })
      end
    end
  end
end
