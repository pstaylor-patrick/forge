# frozen_string_literal: true

require "forge_cli/command_support"

module ForgeCli
  module Commands
    # forge servers: every server in the org.
    class Servers
      COLUMNS = %i[id name ip_address provider region php_version ubuntu_version connection_status].freeze

      def self.run(argv, ctx:, formatter:)
        parser = CommandSupport.parser({}, banner: "servers")
        CommandSupport.parse!(parser, argv, max_args: 0)
        formatter.list("servers", ctx.servers, columns: COLUMNS)
      end
    end
  end
end
