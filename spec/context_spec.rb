# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/fake_client"
require "forge_cli/context"

describe ForgeCli::Context do
  def org(id, slug) = { id: id.to_s, type: "organizations", attributes: { name: slug.upcase, slug: slug } }
  def server(id, name) = { id: id.to_s, type: "servers", attributes: { name: name } }

  def context(org: nil, env: {}, orgs: [org(1, "my-org")], servers: [server(10, "web-1")])
    client = FakeClient.new(fetch_all: { "/orgs" => orgs, "/orgs/my-org/servers" => servers,
                                         "/orgs/other-org/servers" => servers })
    ForgeCli::Context.new(client: client, formatter: nil, org: org, env: env)
  end

  describe "#org" do
    it "uses the --org flag first" do
      ctx = context(org: "other-org", env: { "FORGE_ORG" => "env-org" })
      assert_equal "other-org", ctx.org
      assert_empty ctx.client.calls
    end

    it "uses FORGE_ORG when there is no flag" do
      ctx = context(env: { "FORGE_ORG" => "env-org" })
      assert_equal "env-org", ctx.org
      assert_empty ctx.client.calls
    end

    it "ignores a blank flag or env value" do
      assert_equal "my-org", context(org: " ", env: { "FORGE_ORG" => "" }).org
    end

    it "uses the token's only org" do
      ctx = context
      assert_equal "my-org", ctx.org
      assert_equal "my-org", ctx.org
      assert_equal 1, ctx.client.calls.size
    end

    it "fails listing slugs when several orgs are visible" do
      error = assert_raises(ForgeCli::Error) { context(orgs: [org(1, "my-org"), org(2, "other-org")]).org }
      assert_includes error.message, "my-org, other-org"
      assert_includes error.message, "--org"
    end

    it "fails when the token sees no orgs" do
      assert_raises(ForgeCli::NotFoundError) { context(orgs: []).org }
    end
  end

  describe "#server" do
    it "defaults to the org's only server" do
      assert_equal 10, context.server[:id]
    end

    it "resolves an explicit query by name or id" do
      ctx = context(servers: [server(10, "web-1"), server(11, "web-2")])
      assert_equal 11, ctx.server("web-2")[:id]
      assert_equal 10, ctx.server("10")[:id]
    end

    it "uses FORGE_SERVER when no query is given" do
      ctx = context(env: { "FORGE_SERVER" => "web-2" }, servers: [server(10, "web-1"), server(11, "web-2")])
      assert_equal 11, ctx.server[:id]
    end

    it "prefers the query over FORGE_SERVER" do
      ctx = context(env: { "FORGE_SERVER" => "web-2" }, servers: [server(10, "web-1"), server(11, "web-2")])
      assert_equal 10, ctx.server("web-1")[:id]
    end

    it "fails listing names when several servers exist and none is selected" do
      ctx = context(servers: [server(10, "web-1"), server(11, "web-2")])
      error = assert_raises(ForgeCli::Error) { ctx.server }
      assert_includes error.message, "web-1, web-2"
      assert_includes error.message, "-S/--server"
    end

    it "raises NotFoundError for an unknown server" do
      assert_raises(ForgeCli::NotFoundError) { context.server("no-such-server") }
    end

    it "lists servers once per invocation" do
      ctx = context
      ctx.server
      ctx.server("web-1")
      assert_equal 1, ctx.client.calls.count { |kind, req| kind == :fetch_all && req.path.end_with?("/servers") }
    end
  end

  describe "#site" do
    def site(id, name, server_id: nil)
      record = { id: id.to_s, type: "sites", attributes: { name: name } }
      record[:relationships] = { server: { data: { type: "servers", id: server_id.to_s } } } if server_id
      record
    end

    def site_context(org_sites:, server_sites: {}, servers: [server(10, "web-1"), server(11, "web-2")])
      fetch_all = { "/orgs/my-org/servers" => servers, "/orgs/my-org/sites" => org_sites }
      server_sites.each { |server_id, records| fetch_all["/orgs/my-org/servers/#{server_id}/sites"] = records }
      ForgeCli::Context.new(client: FakeClient.new(fetch_all: fetch_all), formatter: nil, org: "my-org", env: {})
    end

    it "resolves a site name to its server from the org listing" do
      ctx = site_context(org_sites: [site(100, "example.com", server_id: 11), site(101, "api.example.com", server_id: 10)])
      assert_equal({ server_id: 11, site_id: 100, name: "example.com" }, ctx.site("example.com"))
      assert_equal 10, ctx.site("101")[:server_id]
    end

    it "asks the org listing for relationships.server" do
      ctx = site_context(org_sites: [site(100, "example.com", server_id: 11)])
      ctx.site("example.com")
      request = ctx.client.calls.map(&:last).find { |r| r.path == "/orgs/my-org/sites" }
      assert_equal "server", request.query["include"]
    end

    it "lists org sites once per invocation" do
      ctx = site_context(org_sites: [site(100, "example.com", server_id: 11)])
      ctx.site("example.com")
      ctx.site("100")
      assert_equal 1, ctx.client.calls.count { |_, req| req.path == "/orgs/my-org/sites" }
    end

    it "falls back to per-server listings when relationships.server is missing" do
      ctx = site_context(org_sites: [site(100, "example.com")],
                         server_sites: { 10 => [site(101, "api.example.com")], 11 => [site(100, "example.com")] })
      assert_equal({ server_id: 11, site_id: 100, name: "example.com" }, ctx.site("example.com"))
    end

    it "narrows to one server's sites with a server query" do
      ctx = site_context(org_sites: [], server_sites: { 10 => [site(101, "example.com")] })
      assert_equal({ server_id: 10, site_id: 101, name: "example.com" }, ctx.site("example.com", server_query: "web-1"))
      refute(ctx.client.calls.any? { |_, req| req.path == "/orgs/my-org/sites" })
    end

    it "raises NotFoundError listing site names" do
      ctx = site_context(org_sites: [site(100, "example.com", server_id: 11)])
      error = assert_raises(ForgeCli::NotFoundError) { ctx.site("nope.example.com") }
      assert_includes error.message, "available: example.com"
    end

    it "raises AmbiguousError when two servers host the same name" do
      ctx = site_context(org_sites: [site(100, "example.com", server_id: 10), site(200, "example.com", server_id: 11)])
      error = assert_raises(ForgeCli::AmbiguousError) { ctx.site("example.com") }
      assert_includes error.message, "100  example.com"
      assert_equal 200, ctx.site("200")[:site_id]
    end
  end

  describe "child lookups" do
    def named(id, name, type) = { id: id.to_s, type: type, attributes: { name: name } }

    def child_context
      base = "/orgs/my-org/servers/10"
      client = FakeClient.new(fetch_all: {
                                "#{base}/sites/100/domains" => [named(1, "example.com", "domains"),
                                                                named(2, "www.example.com", "domains")],
                                "#{base}/database/schemas" => [named(3, "app_db", "databases")],
                                "#{base}/database/users" => [named(4, "app_user", "databaseUsers")],
                                "#{base}/firewall-rules" => [named(5, "ssh-office", "firewallRules")],
                                "#{base}/scheduled-jobs" => [named(6, "Nightly", "scheduledJobs")],
                                "#{base}/sites/100/scheduled-jobs" => [named(7, "Site job", "scheduledJobs")],
                                "#{base}/background-processes" => [
                                  { id: "8", type: "backgroundProcesses", attributes: { command: "php artisan horizon" } }
                                ]
                              })
      ForgeCli::Context.new(client: client, formatter: nil, org: "my-org", env: {})
    end

    it "resolves each child by name or id" do
      ctx = child_context
      site = { server_id: 10, site_id: 100, name: "example.com" }
      assert_equal 2, ctx.domain(site, "www.example.com")[:id]
      assert_equal 1, ctx.domain(site, "1")[:id]
      assert_equal 3, ctx.schema(10, "app_db")[:id]
      assert_equal 4, ctx.db_user(10, "APP_USER")[:id]
      assert_equal 5, ctx.firewall_rule(10, "ssh-office")[:id]
      assert_equal 6, ctx.job(10, "Nightly")[:id]
      assert_equal 7, ctx.job(10, "7", site: site)[:id]
    end

    it "resolves daemons by id only" do
      ctx = child_context
      assert_equal "php artisan horizon", ctx.daemon(10, "8")[:command]
      assert_raises(ForgeCli::NotFoundError) { ctx.daemon(10, "9") }
      assert_raises(ForgeCli::Error) { ctx.daemon(10, "horizon") }
    end

    it "names the kind when a child is missing" do
      error = assert_raises(ForgeCli::NotFoundError) { child_context.schema(10, "nope") }
      assert_includes error.message, "no database matches 'nope'"
    end
  end
end
