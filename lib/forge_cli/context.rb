# frozen_string_literal: true

require_relative "endpoints"
require_relative "error"
require_relative "records"
require_relative "resolver"

module ForgeCli
  # Per-invocation state: the client, the formatter, stdin, the global --org
  # value, and memoized org and server lookups.
  class Context
    attr_reader :client, :formatter, :stdin

    def initialize(client:, formatter:, org: nil, stdin: $stdin, env: ENV)
      @client = client
      @formatter = formatter
      @org_flag = org
      @stdin = stdin
      @env = env
    end

    # --org, else FORGE_ORG, else the token's only org (by slug).
    def org
      @org ||= present(@org_flag) || present(@env["FORGE_ORG"]) || only_org
    end

    # Raw server records for the org (all pages).
    def servers
      @servers ||= client.fetch_all(Endpoints.servers(org))
    end

    # Flattened listing record for one server: the query (from -S or a
    # positional argument), else FORGE_SERVER, else the org's only server.
    def server(query = nil)
      query = present(query) || present(@env["FORGE_SERVER"])
      records = servers.map { |s| Records.flatten(s) }
      return Resolver.pick(records, query, kind: "server") if query

      only_server(records)
    end

    private

    def only_org
      slugs = client.fetch_all(Endpoints.orgs).map { |o| Records.flatten(o)[:slug] }
      case slugs.size
      when 1 then slugs.first
      when 0 then raise NotFoundError, "token sees no organizations"
      else raise Error, "several orgs visible: #{slugs.join(', ')}; pass --org or set FORGE_ORG"
      end
    end

    def only_server(records)
      case records.size
      when 1 then records.first
      when 0 then raise NotFoundError, "no servers in org #{org}"
      else
        names = records.map { |r| r[:name] }.join(", ")
        raise Error, "several servers in org #{org}: #{names}; pass -S/--server or set FORGE_SERVER"
      end
    end

    def present(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
