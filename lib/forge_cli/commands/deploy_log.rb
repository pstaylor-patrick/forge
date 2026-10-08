# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge deploy-log SITE [DEPLOYMENT_ID]: a deployment's output (default:
    # the latest deployment).
    class DeployLog
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "deploy-log SITE [DEPLOYMENT_ID] [-S SERVER]", server: true)
        query, deployment_id = CommandSupport.parse!(parser, argv, max_args: 2)
        raise Error, "missing SITE\n#{parser.banner}" if query.nil?

        ref = ctx.site(query, server_query: opts[:server])
        deployment_id ||= latest_id(ctx, ref)
        body = ctx.client.fetch(Endpoints.deployment_log(ctx.org, ref[:server_id], ref[:site_id], deployment_id))
        output = body.dig(:data, :attributes, :output) || body[:raw]
        formatter.text("deploy-log", output.to_s, meta: { site: ref[:name], deployment_id: deployment_id.to_s })
      end

      def self.latest_id(ctx, ref)
        latest = Array(ctx.client.fetch(Endpoints.deployments(ctx.org, ref[:server_id], ref[:site_id], size: 1))[:data]).first
        raise NotFoundError, "site #{ref[:name]} has no deployments" unless latest

        latest[:id]
      end
      private_class_method :latest_id
    end
  end
end
