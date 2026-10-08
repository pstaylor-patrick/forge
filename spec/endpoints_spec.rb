# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "forge_cli/endpoints"

describe ForgeCli::Endpoints do
  E = ForgeCli::Endpoints

  it "builds the account and org reads" do
    assert_equal ForgeCli::Request.new(method: "GET", path: "/user"), E.user
    assert_equal "/orgs", E.orgs.path
    assert_equal({}, E.orgs.query)
    assert_nil E.orgs.body
  end

  it "builds server paths under the org" do
    assert_equal "/orgs/my-org/servers", E.servers("my-org").path
    assert_equal "/orgs/my-org/servers/42", E.server("my-org", 42).path
    assert_equal "GET", E.server("my-org", 42).method
  end

  it "encodes path segments built from names" do
    assert_equal "/orgs/my+org%2Fx/servers", E.servers("my org/x").path
  end

  it "keeps query keys literal so the client can encode the brackets" do
    request = E.get("/orgs", { "page[size]" => 30 })
    assert_equal({ "page[size]" => 30 }, request.query)
    assert_equal "page%5Bsize%5D=30", URI.encode_www_form(request.query)
  end

  it "drops nil body keys, including nested ones" do
    body = E.compact_body({ a: 1, b: nil, c: { d: nil, e: "x" }, f: false })
    assert_equal({ a: 1, c: { e: "x" }, f: false }, body)
  end

  it "defaults query to {} and body to nil on Request" do
    request = ForgeCli::Request.new(method: "POST", path: "/x")
    assert_equal({}, request.query)
    assert_nil request.body
    assert_equal({ k: 1 }, request.with(body: { k: 1 }).body)
  end

  describe "site and resource reads" do
    SITE = "/orgs/my-org/servers/10/sites/20"

    it "asks the org-wide site endpoints to include the server" do
      assert_equal "/orgs/my-org/sites", E.org_sites("my-org").path
      assert_equal({ "include" => "server" }, E.org_sites("my-org").query)
      assert_equal "/orgs/my-org/sites/20", E.org_site("my-org", 20).path
      assert_equal({ "include" => "server" }, E.org_site("my-org", 20).query)
      assert_equal "/orgs/my-org/servers/10/sites", E.server_sites("my-org", 10).path
    end

    it "sorts deployments newest first with a page size" do
      request = E.deployments("my-org", 10, 20, size: 3)
      assert_equal "#{SITE}/deployments", request.path
      assert_equal "sort=-created_at&page%5Bsize%5D=3", URI.encode_www_form(request.query)
    end

    it "builds the deployment, env, domain, and certificate paths" do
      assert_equal "#{SITE}/deployments/5", E.deployment("my-org", 10, 20, 5).path
      assert_equal "#{SITE}/deployments/5/log", E.deployment_log("my-org", 10, 20, 5).path
      assert_equal "#{SITE}/deployments/status", E.deployment_status("my-org", 10, 20).path
      assert_equal "#{SITE}/deployments/script", E.deploy_script("my-org", 10, 20).path
      assert_equal "#{SITE}/environment", E.environment("my-org", 10, 20).path
      assert_equal "#{SITE}/domains", E.domains("my-org", 10, 20).path
      assert_equal "#{SITE}/certificates", E.site_certificates("my-org", 10, 20).path
    end

    it "builds site logs for the three known types only" do
      %w[application nginx-access nginx-error].each do |type|
        assert_equal "#{SITE}/logs/#{type}", E.site_log("my-org", 10, 20, type).path
      end
      assert_raises(ArgumentError) { E.site_log("my-org", 10, 20, "../environment") }
    end

    it "builds the server resource paths" do
      server = "/orgs/my-org/servers/10"
      assert_equal "#{server}/database/schemas", E.schemas("my-org", 10).path
      assert_equal "#{server}/database/users", E.db_users("my-org", 10).path
      assert_equal "#{server}/background-processes", E.daemons("my-org", 10).path
      assert_equal "#{server}/background-processes/7/log", E.daemon_log("my-org", 10, 7).path
      assert_equal "#{server}/firewall-rules", E.firewall_rules("my-org", 10).path
      assert_equal "#{server}/scheduled-jobs", E.server_jobs("my-org", 10).path
      assert_equal "#{SITE}/scheduled-jobs", E.site_jobs("my-org", 10, 20).path
      assert_equal "#{server}/scheduled-jobs/8/output", E.server_job_output("my-org", 10, 8).path
      assert_equal "#{SITE}/scheduled-jobs/8/output", E.site_job_output("my-org", 10, 20, 8).path
      assert_equal "#{server}/events/9/output", E.event_output("my-org", 10, 9).path
    end

    it "encodes a server log key as one path segment" do
      assert_equal "/orgs/my-org/servers/10/logs/php-8.4", E.server_log("my-org", 10, "php-8.4").path
      assert_equal "/orgs/my-org/servers/10/logs/..%2Fx", E.server_log("my-org", 10, "../x").path
    end

    it "sorts events newest first at org and server scope" do
      assert_equal "/orgs/my-org/events", E.org_events("my-org", size: 5).path
      assert_equal "/orgs/my-org/servers/10/events", E.server_events("my-org", 10, size: 5).path
      assert_equal({ "sort" => "-created_at", "page[size]" => 5 }, E.org_events("my-org", size: 5).query)
    end

    it "matches a GET path template in the OpenAPI snapshot for every read builder" do
      spec = JSON.parse(File.read(File.expand_path("../docs/forge-openapi.json", __dir__)))
      templates = spec["paths"].select { |_, ops| ops.key?("get") }.keys.map do |t|
        Regexp.new("\\A/?#{t.sub(%r{\A/}, '').gsub(/\{[^}]+\}/, '[^/]+')}\\z")
      end
      requests = [
        E.org_sites("o"), E.org_site("o", 2), E.server_sites("o", 1), E.deployments("o", 1, 2, size: 1),
        E.deployment("o", 1, 2, 3), E.deployment_log("o", 1, 2, 3), E.deployment_status("o", 1, 2),
        E.deploy_script("o", 1, 2), E.environment("o", 1, 2), E.domains("o", 1, 2), E.site_certificates("o", 1, 2),
        E.schemas("o", 1), E.db_users("o", 1), E.daemons("o", 1), E.daemon_log("o", 1, 3), E.firewall_rules("o", 1),
        E.server_jobs("o", 1), E.site_jobs("o", 1, 2), E.server_job_output("o", 1, 3), E.site_job_output("o", 1, 2, 3),
        E.org_events("o", size: 1), E.server_events("o", 1, size: 1), E.event_output("o", 1, 3),
        E.server_log("o", 1, "nginx-access"), *E::SITE_LOG_TYPES.map { |t| E.site_log("o", 1, 2, t) }
      ]
      requests.each do |request|
        assert_equal "GET", request.method
        assert(templates.any? { |re| re.match?(request.path) }, "no GET template matches #{request.path}")
      end
    end
  end

  describe "write builders" do
    it "queues a deployment with a bodyless POST" do
      request = E.deploy("my-org", 10, 20)
      assert_equal ["POST", "/orgs/my-org/servers/10/sites/20/deployments", nil], [request.method, request.path, request.body]
    end

    it "sends the env file under environment, not content, and drops unset flags" do
      request = E.put_environment("my-org", 10, 20, content: "A=1\n")
      assert_equal "PUT", request.method
      assert_equal "/orgs/my-org/servers/10/sites/20/environment", request.path
      assert_equal({ environment: "A=1\n" }, request.body)
      assert_equal({ environment: "", cache: true, queues: false },
                   E.put_environment("o", 1, 2, content: "", cache: true, queues: false).body)
    end

    it "keeps auto_source false but drops it when nil" do
      assert_equal({ content: "x" }, E.put_deploy_script("o", 1, 2, content: "x").body)
      assert_equal({ content: "x", auto_source: false }, E.put_deploy_script("o", 1, 2, content: "x", auto_source: false).body)
      assert_equal "/orgs/o/servers/1/sites/2/deployments/script", E.put_deploy_script("o", 1, 2, content: "x").path
    end

    it "builds the database schema and user writes, dropping unset keys" do
      assert_equal ["POST", "/orgs/o/servers/1/database/schemas", { name: "app" }],
                   E.create_schema("o", 1, name: "app").then { |r| [r.method, r.path, r.body] }
      assert_equal ["DELETE", "/orgs/o/servers/1/database/schemas/60", nil],
                   E.delete_schema("o", 1, 60).then { |r| [r.method, r.path, r.body] }
      assert_equal({ name: "u", password: "p", read_only: false },
                   E.create_db_user("o", 1, name: "u", password: "p", read_only: false).body)
      assert_equal ["PUT", "/orgs/o/servers/1/database/users/70", { database_ids: [] }],
                   E.update_db_user("o", 1, 70, database_ids: []).then { |r| [r.method, r.path, r.body] }
      assert_equal ["DELETE", "/orgs/o/servers/1/database/users/70", nil],
                   E.delete_db_user("o", 1, 70).then { |r| [r.method, r.path, r.body] }
    end

    it "builds site writes with domain_mode custom and rejects unknown attributes" do
      request = E.create_site("o", 1, type: "laravel", name: "example.com", php_version: "php84", branch: nil)
      assert_equal ["POST", "/orgs/o/servers/1/sites",
                    { type: "laravel", name: "example.com", domain_mode: "custom", php_version: "php84" }],
                   [request.method, request.path, request.body]
      assert_raises(ArgumentError) { E.create_site("o", 1, type: "laravel", name: "example.com", tags: []) }
      assert_equal ["PUT", "/orgs/o/servers/1/sites/2", { push_to_deploy: false }],
                   E.update_site("o", 1, 2, push_to_deploy: false).then { |r| [r.method, r.path, r.body] }
      assert_raises(ArgumentError) { E.update_site("o", 1, 2, name: "x") }
      assert_equal ["DELETE", "/orgs/o/servers/1/sites/2", nil],
                   E.delete_site("o", 1, 2).then { |r| [r.method, r.path, r.body] }
    end

    it "builds domain and Let's Encrypt certificate writes" do
      assert_equal({ name: "www.example.com", www_redirect_type: "none", allow_wildcard_subdomains: false },
                   E.create_domain("o", 1, 2, name: "www.example.com", www_redirect_type: "none",
                                              allow_wildcard_subdomains: false).body)
      assert_equal "/orgs/o/servers/1/sites/2/domains/80", E.delete_domain("o", 1, 2, 80).path
      request = E.issue_certificate("o", 1, 2, 80, verification_method: "http-01", key_type: "ecdsa")
      assert_equal ["POST", "/orgs/o/servers/1/sites/2/domains/80/certificates",
                    { type: "letsencrypt", letsencrypt: { verification_method: "http-01", key_type: "ecdsa" } }],
                   [request.method, request.path, request.body]
      assert_equal ["DELETE", "/orgs/o/servers/1/sites/2/domains/80/certificates/90"],
                   E.delete_certificate("o", 1, 2, 80, 90).then { |r| [r.method, r.path] }
    end
  end
end
