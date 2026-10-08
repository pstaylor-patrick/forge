# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge deploy-script SITE: the site's deploy script on stdout, and
    # auto_source on stderr so stdout is exactly the script.
    class DeployScript
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "deploy-script SITE [-S SERVER]", server: true)
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        ref = ctx.site(query, server_query: opts[:server])
        attrs = ctx.client.fetch(Endpoints.deploy_script(ctx.org, ref[:server_id], ref[:site_id])).dig(:data, :attributes) || {}
        formatter.text("deploy-script", attrs[:content].to_s,
                       meta: { site: ref[:name], auto_source: attrs[:auto_source] }, footer: [:auto_source])
      end
    end
  end
end
