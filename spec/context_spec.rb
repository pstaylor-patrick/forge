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
end
