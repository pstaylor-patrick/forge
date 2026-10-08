# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/fake_client"
require "json"
require "forge_cli/context"
require "forge_cli/formatter"

# Read commands end to end against canned responses: no network.
describe "read commands" do
  ORG = "/orgs/my-org"
  SITE_PATH = "#{ORG}/servers/10/sites/20".freeze
  ENV_CONTENT = "APP_KEY=base64:topsecret\nDB_PASSWORD=\"hunter2 x\"\nEMPTY=\n# note\n".freeze

  def site_record
    { id: "20", type: "sites", attributes: { name: "example.com", php_version: "PHP 8.4",
                                             repository: { provider: "github", url: "https://github.com/acme/app",
                                                           branch: "main", status: "installed" } },
      relationships: { server: { data: { type: "servers", id: "10" } } } }
  end

  def deployment(id, created_at)
    { id: id.to_s, type: "deployments",
      attributes: { status: "finished", created_at: created_at,
                    commit: { hash: "abcdef1234", message: "Fix it\n\nbody", author: "a", branch: "main" } } }
  end

  def client
    FakeClient.new(
      fetch_all: { "#{ORG}/servers" => [{ id: "10", type: "servers", attributes: { name: "web-1" } }],
                   "#{ORG}/sites" => [site_record] },
      fetch: { "#{SITE_PATH}/environment" => { data: { attributes: { content: ENV_CONTENT } } },
               "#{SITE_PATH}/deployments" => { data: [deployment(2, "2026-01-02"), deployment(1, "2026-01-01")] },
               "#{SITE_PATH}/deployments/2/log" => { data: { attributes: { output: "line 1\nline 2\n" } } },
               "#{SITE_PATH}/deployments/script" => { data: { attributes: { content: "cd /x\ngit pull\n",
                                                                            auto_source: false } } },
               "#{SITE_PATH}/deployments/status" => { data: { attributes: { status: nil, started_at: nil } } },
               "#{SITE_PATH}/logs/application" => { data: { attributes: { content: "a\nb\nc\n" } },
                                                    meta: { log: "site" } },
               "#{ORG}/sites/20" => { data: site_record } }
    )
  end

  def run_command(name, argv, json: false)
    require "forge_cli/commands/#{name.tr('-', '_')}"
    klass = ForgeCli::Commands.const_get(name.split(/[-_]/).map(&:capitalize).join)
    formatter = json ? ForgeCli::JsonFormatter : ForgeCli::Formatter
    fake = client
    ctx = ForgeCli::Context.new(client: fake, formatter: formatter, org: "my-org", env: {})
    out, err = capture_io { klass.run(argv, ctx: ctx, formatter: formatter) }
    [out, err, fake]
  end

  describe "env" do
    it "masks every value by default" do
      out, = run_command("env", ["example.com"])
      assert_equal "APP_KEY=********\nDB_PASSWORD=********\nEMPTY=\n# note\n", out
      %w[topsecret hunter2].each { |secret| refute_includes out, secret }
    end

    it "masks JSON output by default and omits the raw content" do
      out, = run_command("env", ["example.com"], json: true)
      data = JSON.parse(out)["data"]
      assert_equal false, data["revealed"]
      refute data.key?("content")
      assert_equal [{ "key" => "APP_KEY", "value" => "********" }, { "key" => "DB_PASSWORD", "value" => "********" },
                    { "key" => "EMPTY", "value" => "" }], data["entries"]
      %w[topsecret hunter2].each { |secret| refute_includes out, secret }
    end

    it "prints raw content with --reveal" do
      out, = run_command("env", ["example.com", "--reveal"])
      assert_equal ENV_CONTENT, out
      json, = run_command("env", ["example.com", "--reveal"], json: true)
      data = JSON.parse(json)["data"]
      assert_equal true, data["revealed"]
      assert_equal "hunter2 x", data["entries"][1]["value"]
    end
  end

  it "lists deployments newest first with a commit summary" do
    out, _, fake = run_command("deploys", ["example.com", "-n", "2"])
    request = fake.calls.map(&:last).find { |r| r.path == "#{SITE_PATH}/deployments" }
    assert_equal({ "sort" => "-created_at", "page[size]" => 2 }, request.query)
    assert_includes out, "abcdef1 Fix it"
    assert_operator out.index("2026-01-02"), :<, out.index("2026-01-01")
  end

  it "prints the latest deployment's log by default" do
    out, = run_command("deploy-log", ["example.com"])
    assert_equal "line 1\nline 2\n", out
  end

  it "keeps the deploy script alone on stdout" do
    out, err = run_command("deploy-script", ["example.com"])
    assert_equal "cd /x\ngit pull\n", out
    assert_equal "auto_source: false\n", err
  end

  it "shows idle when no deployment is running" do
    out, = run_command("deploy-status", ["example.com"])
    assert_match(/status:\s+idle/, out)
  end

  it "tails a site log" do
    out, = run_command("logs", ["example.com", "--tail", "2"])
    assert_equal "b\nc\n", out
    all, = run_command("logs", ["example.com", "--tail", "0"])
    assert_equal "a\nb\nc\n", all
  end

  it "rejects an unknown log type before any request" do
    error = assert_raises(ForgeCli::Error) { run_command("logs", ["example.com", "--type", "environment"]) }
    assert_includes error.message, "application, nginx-access, nginx-error"
  end

  it "shows a site's server id and repository" do
    out, = run_command("site", ["example.com"])
    assert_match(/server_id:\s+10/, out)
    assert_match(%r{repository:\s+https://github.com/acme/app \(main\)}, out)
  end

  it "shows server ids in the site list" do
    out, = run_command("sites", [])
    row = out.lines.find { |l| l.start_with?("20") }
    assert_equal %w[20 example.com 10 PHP 8.4 -], row.split.first(6)
  end

  it "requires a SITE argument" do
    error = assert_raises(ForgeCli::Error) { run_command("env", []) }
    assert_includes error.message, "missing SITE"
  end
end
