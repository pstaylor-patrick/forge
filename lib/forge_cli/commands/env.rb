# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge env SITE [--reveal]: the site's .env with every value masked;
    # --reveal prints the raw file.
    class Env
      def self.run(argv, ctx:, formatter:)
        opts = { reveal: false }
        parser = CommandSupport.parser(opts, banner: "env SITE [--reveal] [-S SERVER]", server: true) do |o|
          o.on("--reveal", "Print raw values (secrets) instead of masking them") { opts[:reveal] = true }
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        content = ctx.client.fetch(Endpoints.environment(ctx.org, ref[:server_id], ref[:site_id]))
                     .dig(:data, :attributes, :content).to_s
        formatter.env("env", ref[:name], content, revealed: opts[:reveal])
      end
    end
  end
end
