# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge firewall-create --name NAME [--port PORT] [--ip ADDR] [--type allow|deny] [-S SERVER]
    # Adds a firewall rule. Not guarded: it removes nothing.
    class FirewallCreate
      MAX_NAME = 50
      PORT = /\A\d+([:-]\d+)?\z/

      def self.run(argv, ctx:, formatter:)
        opts = { type: "allow" }
        parser = CommandSupport.parser(opts, banner: "firewall-create --name NAME [--port PORT] [--ip ADDR] " \
                                                     "[--type allow|deny] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--name NAME", "Rule name (max #{MAX_NAME} characters)") { |v| opts[:name] = v }
          o.on("--port PORT", "Port or range, e.g. 8443 or 8000:8010") { |v| opts[:port] = v }
          o.on("--ip ADDR", "IP address or CIDR the rule applies to (default: any)") { |v| opts[:ip] = v }
          o.on("--type TYPE", "allow (default) or deny") { |v| opts[:type] = v }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        name = opts[:name].to_s.strip
        raise Error, "--name is required\n#{parser.banner}" if name.empty?
        raise Error, "--name must be at most #{MAX_NAME} characters (got #{name.length})" if name.length > MAX_NAME

        CommandSupport.one_of!(opts[:type], Endpoints::FIREWALL_TYPES, flag: "--type")
        port = opts[:port]&.strip
        if port && !port.match?(PORT)
          raise Error, "--port must be a port or range such as 8443 or 8000:8010, got '#{port}'"
        end

        server = ctx.server(opts[:server])
        org = ctx.org
        request = Endpoints.create_firewall_rule(org, server[:id], name: name, type: opts[:type], port: port,
                                                                   ip_address: opts[:ip]&.strip)
        CommandSupport.write!(ctx, command: "firewall-create", request: request, opts: opts,
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Created firewall rule #{[id, "(#{name})"].compact.join(' ')} on #{server[:name]}"
                                   })
      end
    end
  end
end
