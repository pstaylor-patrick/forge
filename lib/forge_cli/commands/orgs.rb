# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"

module ForgeCli
  module Commands
    # forge orgs: organizations the token can see.
    class Orgs
      COLUMNS = %i[id slug name].freeze

      def self.run(argv, ctx:, formatter:)
        parser = CommandSupport.parser({}, banner: "orgs")
        CommandSupport.parse!(parser, argv, max_args: 0)
        formatter.list("orgs", ctx.client.fetch_all(Endpoints.orgs), columns: COLUMNS)
      end
    end
  end
end
