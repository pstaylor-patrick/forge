# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge deploy-status SITE: whether a deployment is running ("idle" when not).
    class DeployStatus
      FIELDS = %i[status started_at].freeze

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "deploy-status SITE [-S SERVER]", server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        record = ctx.client.fetch(Endpoints.deployment_status(ctx.org, ref[:server_id], ref[:site_id]))[:data]
        derive = ->(r) { { status: r.dig(:attributes, :status) || "idle" } }
        formatter.show("deploy-status", record, fields: FIELDS, derive: derive)
      end
    end
  end
end
