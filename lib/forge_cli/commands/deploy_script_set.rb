# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge deploy-script-set SITE (--file PATH | --stdin) [--[no-]auto-source]
    # Replaces the site's deploy script. Destructive (it overwrites the script),
    # so it takes the typed-name guard or --yes.
    class DeployScriptSet
      SOURCES = "--file PATH or --stdin"

      def self.run(argv, ctx:, formatter:, err: $stderr)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "deploy-script-set SITE (--file PATH | --stdin) " \
                                                     "[--[no-]auto-source] [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true) do |o|
          o.on("--file PATH", "Replace the script with this file") { |v| opts[:file] = v }
          o.on("--stdin", "Replace the script with stdin (needs --yes: stdin is not a TTY)") { opts[:stdin] = true }
          o.on("--[no-]auto-source", "Source the site's .env before the script runs") { |v| opts[:auto_source] = v }
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        content = CommandSupport.read_source(opts, ctx.stdin, flag_help: SOURCES)
        raise Error, "the new deploy script is empty; refusing to send it" if content.strip.empty?

        ref = ctx.site(query, server_query: opts[:server])
        org = ctx.org
        current = ctx.client.fetch(Endpoints.deploy_script(org, ref[:server_id], ref[:site_id])).dig(:data, :attributes) || {}
        same_auto_source = opts[:auto_source].nil? || opts[:auto_source] == current[:auto_source]
        if same_auto_source && CommandSupport.same_text?(content, current[:content])
          formatter.unchanged("deploy-script-set")
          return nil
        end

        err.puts "#{current[:content].to_s.lines.size} lines -> #{content.lines.size} lines"
        request = Endpoints.put_deploy_script(org, ref[:server_id], ref[:site_id], content: content,
                                                                                   auto_source: opts[:auto_source])
        CommandSupport.write!(
          ctx, command: "deploy-script-set", request: request, opts: opts,
               affected: CommandSupport.site_affected(org, ref),
               confirm: CommandSupport.site_confirm("replace the deploy script", ref),
               summary: ->(_) { "Updated the deploy script for #{ref[:name]}" }
        )
      end
    end
  end
end
