# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/records"

module ForgeCli
  module Commands
    # forge deploys SITE [-n N]: a site's most recent deployments, newest first.
    class Deploys
      COLUMNS = %i[id status commit created_at ended_at].freeze
      DEFAULT_COUNT = 10
      MAX_COUNT = 100

      def self.run(argv, ctx:, formatter:)
        opts = { count: DEFAULT_COUNT }
        parser = CommandSupport.parser(opts, banner: "deploys SITE [-n N] [-S SERVER]", server: true) do |o|
          o.on("-n", "--limit N", "How many (default #{DEFAULT_COUNT}, max #{MAX_COUNT})") do |v|
            opts[:count] = CommandSupport.count(v, flag: "-n", max: MAX_COUNT)
          end
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        request = Endpoints.deployments(ctx.org, ref[:server_id], ref[:site_id], size: opts[:count])
        records = Array(ctx.client.fetch(request)[:data]).first(opts[:count])
        formatter.list("deploys", records, columns: COLUMNS, derive: ->(r) { { commit: Records.dig_commit(r) } })
      end
    end
  end
end
