# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge site-update SITE [--php phpNN] [--type T] [--directory DIR]
    #   [--root-path P] [--branch B] [--[no-]push-to-deploy]
    #   [--deployment-retention N]
    # Changes a site's settings. Only the given flags are sent. Not guarded.
    class SiteUpdate
      MAX_RETENTION = 100

      def self.run(argv, ctx:, formatter:)
        attrs = {}
        opts = {}
        parser = CommandSupport.parser(opts, banner: "site-update SITE [--php phpNN] [--type T] [--directory DIR] " \
                                                     "[--root-path P] [--branch B] [--[no-]push-to-deploy] " \
                                                     "[--deployment-retention N] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--php VERSION", "PHP version, e.g. php84") { |v| attrs[:php_version] = v }
          o.on("--type TYPE", "Site type: #{Endpoints::SITE_TYPES.join(', ')}") { |v| attrs[:type] = v }
          o.on("--directory DIR", "Web directory, e.g. /public") { |v| attrs[:directory] = v }
          o.on("--root-path PATH", "Root path of the site") { |v| attrs[:root_path] = v }
          o.on("--branch BRANCH", "Repository branch to deploy") { |v| attrs[:repository_branch] = v }
          o.on("--[no-]push-to-deploy", "Deploy on every push to the branch") { |v| attrs[:push_to_deploy] = v }
          o.on("--deployment-retention N", "Zero-downtime releases to keep (1..#{MAX_RETENTION})") do |v|
            attrs[:deployment_retention] = CommandSupport.count(v, flag: "--deployment-retention", max: MAX_RETENTION)
          end
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        raise Error, "give at least one setting to change\n#{parser.banner}" if attrs.empty?

        CommandSupport.one_of!(attrs[:php_version], Endpoints::PHP_VERSIONS, flag: "--php") if attrs[:php_version]
        CommandSupport.one_of!(attrs[:type], Endpoints::SITE_TYPES, flag: "--type") if attrs[:type]

        ref = ctx.site(query, server_query: opts[:server])
        org = ctx.org
        request = Endpoints.update_site(org, ref[:server_id], ref[:site_id], **attrs)
        changed = attrs.keys.join(", ")
        CommandSupport.write!(ctx, command: "site-update", request: request, opts: opts,
                                   affected: CommandSupport.site_affected(org, ref),
                                   summary: ->(_) { "Updated site #{ref[:site_id]} (#{ref[:name]}): #{changed}" })
      end
    end
  end
end
