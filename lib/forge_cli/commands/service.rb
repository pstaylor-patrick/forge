# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge service SERVICE ACTION [--php-version phpNN] [-S SERVER]
    # Runs a service action. restart is an alias sent as reboot. stop takes a
    # service down without bringing it back, so it is guarded (the user types
    # the server name); the other actions are not.
    class Service
      ALIASES = { "restart" => "reboot" }.freeze
      GUARDED = %w[stop].freeze
      PHP_VERSION = /\Aphp\d+\z/

      # Every action the CLI accepts per service: the API's, plus restart.
      def self.actions
        Endpoints::SERVICE_ACTIONS.transform_values { |api| (ALIASES.keys + api).uniq }
      end

      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "service SERVICE ACTION [--php-version phpNN] [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true) do |o|
          o.on("--php-version VERSION", "PHP version for the php service, e.g. php84 " \
                                        "(default: the server's php_version)") { |v| opts[:php_version] = v }
        end
        service, action = parse_args(parser, argv)
        validate!(service, action, opts)

        server = ctx.server(opts[:server])
        org = ctx.org
        version = php_version(service, opts, server)
        api_action = ALIASES.fetch(action, action)
        target = service == "php" ? "#{service} (#{version})" : service
        confirm = if GUARDED.include?(action)
                    { action: "stop #{target} on server #{server[:name]} (id #{server[:id]}); " \
                              "it stays down until started again", token: server[:name] }
                  end
        request = Endpoints.service_action(org, server[:id], service, action: api_action, version: version)
        CommandSupport.write!(ctx, command: "service", request: request, opts: opts, confirm: confirm,
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: ->(_) { "Sent #{api_action} to #{target} on #{server[:name]}" })
      end

      def self.parse_args(parser, argv)
        args = CommandSupport.parse!(parser, argv, max_args: 2)
        raise Error, "missing SERVICE and ACTION\n#{parser.banner}" if args.size < 2

        args.map(&:downcase)
      end

      # Checked against the action table before any request is made.
      def self.validate!(service, action, opts)
        allowed = actions
        unless allowed.key?(service)
          raise Error, "unknown service '#{service}'; one of #{allowed.keys.join(', ')}"
        end
        unless allowed[service].include?(action)
          raise Error, "#{service} does not support '#{action}'; it supports #{allowed[service].join(', ')}"
        end
        raise Error, "--php-version only applies to the php service" if opts[:php_version] && service != "php"
        return unless opts[:php_version] && !opts[:php_version].match?(PHP_VERSION)

        raise Error, "--php-version must look like php84, got '#{opts[:php_version]}'"
      end

      def self.php_version(service, opts, server)
        return nil unless service == "php"

        version = opts[:php_version] || server[:php_version]
        raise Error, "server #{server[:name]} reports no php_version; pass --php-version phpNN" if version.to_s.empty?

        version
      end

      private_class_method :parse_args, :validate!, :php_version
    end
  end
end
