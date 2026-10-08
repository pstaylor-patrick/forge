# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge me: the user that owns FORGE_API_KEY.
    class Me
      FIELDS = %i[id name email].freeze

      def self.run(argv, ctx:, formatter:)
        parser = CommandSupport.parser({}, banner: "me")
        CommandSupport.parse!(parser, argv, max_args: 0)
        body = ctx.client.fetch(Endpoints.user)
        formatter.show("me", body[:data], fields: FIELDS)
      end
    end
  end
end
