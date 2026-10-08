# frozen_string_literal: true

require_relative "endpoints"
require_relative "error"
require_relative "records"
require_relative "resolver"

module ForgeCli
  # Per-invocation state: the client, the formatter, stdin, the global --org
  # value, memoized org, server, and site lookups, and child lookups.
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

    # Resolves a site name (its domain) or id to {server_id:, site_id:, name:}.
    # With server_query (-S), lists only that server's sites. Otherwise lists
    # the org's sites (include=server) and reads relationships.server; if that
    # relationship is missing, finds the site by listing each server's sites.
    def site(query, server_query: nil)
      if present(server_query)
        server_id = server(server_query)[:id]
        record = Resolver.pick(server_site_records(server_id), query, kind: "site")
        return site_ref(server_id, record)
      end

      raw = Resolver.pick(org_site_records, query, kind: "site")
      server_id = raw[:server_id] || server_of_site(raw[:id])
      site_ref(server_id, raw)
    end

    # -- child lookups (name or id) ------------------------------------------

    def domain(site, query) = pick_child(Endpoints.domains(org, site[:server_id], site[:site_id]), query, "domain")
    def schema(server_id, query) = pick_child(Endpoints.schemas(org, server_id), query, "database")
    def db_user(server_id, query) = pick_child(Endpoints.db_users(org, server_id), query, "database user")
    def firewall_rule(server_id, query) = pick_child(Endpoints.firewall_rules(org, server_id), query, "firewall rule")

    # A scheduled job by name or id, on the server or (with site) on that site.
    def job(server_id, query, site: nil)
      request = site ? Endpoints.site_jobs(org, server_id, site[:site_id]) : Endpoints.server_jobs(org, server_id)
      pick_child(request, query, "scheduled job")
    end

    # Daemons have no name attribute, so they resolve by id only.
    def daemon(server_id, id)
      raise Error, "daemon must be a numeric id, got '#{id}'" unless id.to_s.strip.match?(/\A\d+\z/)

      records = client.fetch_all(Endpoints.daemons(org, server_id)).map { |r| Records.flatten(r) }
      Resolver.pick(records, id, kind: "daemon", key: :command)
    end

    private

    # Org sites flattened, with server_id taken from relationships.server.
    def org_site_records
      @org_site_records ||= client.fetch_all(Endpoints.org_sites(org)).map do |r|
        Records.flatten(r).merge(server_id: Records.rel_id(r, :server))
      end
    end

    def server_site_records(server_id)
      @server_site_records ||= {}
      @server_site_records[server_id] ||= client.fetch_all(Endpoints.server_sites(org, server_id))
                                                .map { |r| Records.flatten(r) }
    end

    # Fallback when the org listing lacks relationships.server.
    def server_of_site(site_id)
      servers.each do |s|
        server_id = Records.flatten(s)[:id]
        return server_id if server_site_records(server_id).any? { |r| r[:id] == site_id }
      end
      raise NotFoundError, "could not find the server for site #{site_id}"
    end

    def site_ref(server_id, record) = { server_id: server_id, site_id: record[:id], name: record[:name] }

    def pick_child(request, query, kind)
      Resolver.pick(client.fetch_all(request).map { |r| Records.flatten(r) }, query, kind: kind)
    end

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
