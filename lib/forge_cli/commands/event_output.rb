# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge event-output EVENT_ID [-S SERVER]: an event's output.
    class EventOutput
      def self.run(argv, ctx:, formatter:)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "event-output EVENT_ID [-S SERVER]", server: true)
        id = CommandSupport.one_arg!(parser, argv, "EVENT_ID")
        raise Error, "EVENT_ID must be a numeric id (see forge events), got '#{id}'" unless id.match?(/\A\d+\z/)

        server_id = ctx.server(opts[:server])[:id]
        body = ctx.client.fetch(Endpoints.event_output(ctx.org, server_id, id))
        formatter.text("event-output", (body.dig(:data, :attributes, :output) || body[:raw]).to_s, meta: { event_id: id })
      end
    end
  end
end
