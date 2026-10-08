# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge site-create DOMAIN [-S SERVER] [--type T] [--php phpNN] [--web-dir DIR]
    #   [--repo OWNER/NAME [--branch B] [--provider github|gitlab|bitbucket]]
    #   [--isolated --isolated-user U] [--zero-downtime] [--wildcard]
    #   [--www from-www|to-www|none]
    # Creates a site on a custom domain (domain_mode "custom"). Not guarded:
    # it removes nothing.
    class SiteCreate
      DEFAULT_TYPE = "laravel"
      # Types whose document root is public/; others keep Forge's own default.
      PUBLIC_DIR_TYPES = %w[laravel symfony statamic].freeze
      PUBLIC_DIR = "/public"
      ISOLATED_USER = /\A[a-z][-a-z0-9_]*\z/
      MAX_ISOLATED_USER = 32
      REPOSITORY = %r{\A[^\s/]+(/[^\s/]+)+\z}

      def self.run(argv, ctx:, formatter:)
        opts = { type: DEFAULT_TYPE }
        parser = CommandSupport.parser(opts, banner: "site-create DOMAIN [--type T] [--php phpNN] [--web-dir DIR] " \
                                                     "[--repo OWNER/NAME [--branch B] [--provider P]] " \
                                                     "[--isolated --isolated-user U] [--zero-downtime] [--wildcard] " \
                                                     "[--www from-www|to-www|none] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--type TYPE", "Site type (default #{DEFAULT_TYPE}): #{Endpoints::SITE_TYPES.join(', ')}") { |v| opts[:type] = v }
          o.on("--php VERSION", "PHP version, e.g. php84 (default: the server's)") { |v| opts[:php] = v }
          o.on("--web-dir DIR", "Web directory (default #{PUBLIC_DIR} for #{PUBLIC_DIR_TYPES.join(', ')})") { |v| opts[:web_dir] = v }
          o.on("--repo OWNER/NAME", "Repository to install") { |v| opts[:repo] = v }
          o.on("--branch BRANCH", "Repository branch (needs --repo)") { |v| opts[:branch] = v }
          o.on("--provider PROVIDER", "Source control provider (needs --repo; default github): " \
                                      "#{Endpoints::SOURCE_CONTROL_PROVIDERS.join(', ')}") { |v| opts[:provider] = v }
          o.on("--isolated", "Run the site as its own Linux user (needs --isolated-user)") { opts[:isolated] = true }
          o.on("--isolated-user USER", "The isolated site's Linux user") { |v| opts[:isolated_user] = v }
          o.on("--zero-downtime", "Use zero-downtime deployments") { opts[:zero_downtime] = true }
          o.on("--wildcard", "Answer on every subdomain too") { opts[:wildcard] = true }
          o.on("--www TYPE", "www redirect: #{Endpoints::WWW_REDIRECT_TYPES.join(', ')}") { |v| opts[:www] = v }
        end
        domain = CommandSupport.hostname!(CommandSupport.one_arg!(parser, argv, "DOMAIN"), "DOMAIN")
        attrs = attributes(opts)

        server = ctx.server(opts[:server])
        org = ctx.org
        request = Endpoints.create_site(org, server[:id], type: opts[:type], name: domain, **attrs)
        CommandSupport.write!(ctx, command: "site-create", request: request, opts: opts,
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Created site #{[id, "(#{domain})"].compact.join(' ')} on #{server[:name]}"
                                   })
      end

      # The optional body keys, validated before any request.
      def self.attributes(opts)
        CommandSupport.one_of!(opts[:type], Endpoints::SITE_TYPES, flag: "--type")
        CommandSupport.one_of!(opts[:php], Endpoints::PHP_VERSIONS, flag: "--php") if opts[:php]
        CommandSupport.one_of!(opts[:www], Endpoints::WWW_REDIRECT_TYPES, flag: "--www") if opts[:www]
        web_dir = opts[:web_dir] || (PUBLIC_DIR if PUBLIC_DIR_TYPES.include?(opts[:type]))
        raise Error, "--web-dir must not contain whitespace, got '#{web_dir}'" if web_dir&.match?(/\s/)

        { php_version: opts[:php], web_directory: web_dir, **repository(opts), **isolation(opts),
          zero_downtime_deployments: opts[:zero_downtime], allow_wildcard_subdomains: opts[:wildcard],
          www_redirect_type: opts[:www] }
      end

      def self.repository(opts)
        unless opts[:repo]
          %i[branch provider].each { |key| raise Error, "--#{key} needs --repo" if opts[key] }
          return {}
        end
        raise Error, "--repo must look like OWNER/NAME, got '#{opts[:repo]}'" unless opts[:repo].match?(REPOSITORY)

        provider = opts[:provider] || "github"
        CommandSupport.one_of!(provider, Endpoints::SOURCE_CONTROL_PROVIDERS, flag: "--provider")
        { source_control_provider: provider, repository: opts[:repo], branch: opts[:branch] }
      end

      def self.isolation(opts)
        return {} unless opts[:isolated] || opts[:isolated_user]
        raise Error, "--isolated needs --isolated-user" unless opts[:isolated_user]
        raise Error, "--isolated-user needs --isolated" unless opts[:isolated]

        user = opts[:isolated_user]
        unless user.match?(ISOLATED_USER) && user.length <= MAX_ISOLATED_USER
          raise Error, "--isolated-user must be a lowercase Linux user name of at most #{MAX_ISOLATED_USER} " \
                       "characters, got '#{user}'"
        end
        { is_isolated: true, isolated_user: user }
      end

      private_class_method :attributes, :repository, :isolation
    end
  end
end
