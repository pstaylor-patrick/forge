# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/fake_client"
require_relative "support/tty_input"
require "json"
require "stringio"
require "tempfile"
require "forge_cli/context"
require "forge_cli/formatter"

# Write commands against canned responses. Nothing here opens a socket: every
# "sent" request lands in FakeClient#performed.
describe "write commands" do
  SITE = "/orgs/my-org/servers/10/sites/20"
  SECRET_ENV = "APP_KEY=base64:topsecret\nDB_PASSWORD=\"hunter2 x\"\n# note\n"
  SCRIPT = "cd /home/forge/example.com\ngit pull origin main\n"
  SECRETS = %w[topsecret hunter2].freeze

  def client(deployment_statuses: %w[finished])
    statuses = deployment_statuses.dup
    FakeClient.new(
      fetch_all: { "/orgs/my-org/servers" => [{ id: "10", type: "servers", attributes: { name: "web-1" } }],
                   "/orgs/my-org/sites" => [{ id: "20", type: "sites", attributes: { name: "example.com" },
                                              relationships: { server: { data: { type: "servers", id: "10" } } } }] },
      fetch: { "#{SITE}/environment" => { data: { attributes: { content: SECRET_ENV } } },
               "#{SITE}/deployments/script" => { data: { attributes: { content: SCRIPT, auto_source: false } } },
               "#{SITE}/deployments/99" => lambda { |_|
                 status = statuses.size > 1 ? statuses.shift : statuses.first
                 { data: { id: "99", type: "deployments", attributes: { status: status } } }
               } },
      perform: { "#{SITE}/deployments" => { data: { id: "99", type: "deployments", attributes: { status: "queued" } } },
                 "#{SITE}/environment" => { data: { attributes: { content: SECRET_ENV } } } }
    )
  end

  # Runs a command; returns {out:, err:, result:, client:}. stdin defaults to
  # a non-TTY, like an agent or a pipe.
  def run_write(name, argv, stdin: StringIO.new(""), json: false, fake: client, **kwargs)
    require "forge_cli/commands/#{name.tr('-', '_')}"
    klass = ForgeCli::Commands.const_get(name.split(/[-_]/).map(&:capitalize).join)
    formatter = json ? ForgeCli::JsonFormatter : ForgeCli::Formatter
    ctx = ForgeCli::Context.new(client: fake, formatter: formatter, org: "my-org", stdin: stdin, env: {})
    result = nil
    out, err = capture_io { result = klass.run(argv, ctx: ctx, formatter: formatter, **kwargs) }
    { out: out, err: err, result: result, client: fake }
  end

  def script_file(content)
    file = Tempfile.new("deploy-script")
    file.write(content)
    file.flush
    (@files ||= []) << file
    file.path
  end

  DRY_RUNS = {
    "deploy" => [["example.com", "-d"], "POST", "#{SITE}/deployments"],
    "env-set" => [["example.com", "--set", "NEW_KEY=1", "-d"], "PUT", "#{SITE}/environment"],
    "deploy-script-set" => [["example.com", "--stdin", "-d"], "PUT", "#{SITE}/deployments/script"]
  }.freeze

  describe "-d/--dry-run" do
    DRY_RUNS.each do |name, (argv, method, path)|
      it "#{name}: prints the request and sends nothing" do
        run = run_write(name, argv, stdin: StringIO.new("echo new\n"))
        assert_empty run[:client].performed
        assert_nil run[:result]
        assert_includes run[:out], "DRY RUN (nothing sent)"
        assert_includes run[:out], "#{method} #{path}"
      end

      it "#{name}: emits a dry_run envelope with -j" do
        run = run_write(name, argv, stdin: StringIO.new("echo new\n"), json: true)
        assert_empty run[:client].performed
        json = JSON.parse(run[:out])
        assert_equal true, json["ok"]
        assert_equal name, json["command"]
        assert_equal true, json.dig("data", "dry_run")
        assert_equal method, json.dig("data", "request", "method")
        assert_equal path, json.dig("data", "request", "path")
      end

      it "#{name}: never prompts, even on a TTY" do
        stdin = TtyInput.new("")
        run = run_write(name, argv.reject { |a| a == "--stdin" } + (name == "deploy-script-set" ? ["--file", script_file("x\n")] : []),
                        stdin: stdin)
        assert_empty run[:client].performed
        refute_includes run[:err], "Type example.com"
      end
    end
  end

  describe "guarded commands" do
    GUARDED = {
      "env-set" => [["example.com", "--set", "NEW_KEY=1"], "#{SITE}/environment"],
      "deploy-script-set" => [["example.com", "--file", :script], "#{SITE}/deployments/script"]
    }.freeze

    GUARDED.each do |name, (argv, path)|
      it "#{name}: refuses a non-TTY stdin without --yes and sends nothing" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        fake = client
        assert_raises(ForgeCli::GuardRefused) { run_write(name, args, fake: fake) }
        assert_empty fake.performed
      end

      it "#{name}: sends exactly one PUT with --yes and returns the affected site" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        run = run_write(name, args + ["--yes"])
        assert_equal 1, run[:client].performed.size
        request = run[:client].performed.first
        assert_equal "PUT", request.method
        assert_equal path, request.path
        assert_equal ForgeCli::Affected.new(org: "my-org", server_id: 10, site_id: 20), run[:result]
      end

      it "#{name}: sends after the site name is typed on a TTY" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        run = run_write(name, args, stdin: TtyInput.new("example.com\n"))
        assert_equal 1, run[:client].performed.size
        assert_includes run[:err], "Type example.com to confirm"
      end

      it "#{name}: aborts on a wrong name and sends nothing" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        fake = client
        assert_raises(ForgeCli::Aborted) { run_write(name, args, stdin: TtyInput.new("example.org\n"), fake: fake) }
        assert_empty fake.performed
      end
    end
  end

  describe "deploy" do
    it "queues a deployment without a guard and returns the affected site" do
      run = run_write("deploy", ["example.com"])
      assert_equal [["POST", "#{SITE}/deployments", nil]], run[:client].performed.map { |r| [r.method, r.path, r.body] }
      assert_equal "Deployment 99 queued for example.com\n", run[:out]
      assert_equal 20, run[:result].site_id
    end

    it "prints the deployment record with -j" do
      run = run_write("deploy", ["example.com"], json: true)
      assert_equal "99", JSON.parse(run[:out]).dig("data", "id")
    end

    it "waits for the deployment to finish with --wait" do
      slept = []
      run = run_write("deploy", ["example.com", "--wait"], fake: client(deployment_statuses: %w[deploying finished]),
                                                            sleeper: ->(s) { slept << s }, clock: -> { 0 })
      assert_equal [5], slept
      assert_equal "Deployment 99 finished for example.com\n", run[:out]
      assert_includes run[:err], "deployment 99: deploying"
      assert_equal 1, run[:client].performed.size
    end

    it "raises DeployFailed carrying the affected site when the deployment fails" do
      error = assert_raises(ForgeCli::DeployFailed) do
        run_write("deploy", ["example.com", "-w"], fake: client(deployment_statuses: %w[failed]),
                                                   sleeper: ->(_) {}, clock: -> { 0 })
      end
      assert_includes error.message, "forge deploy-log example.com 99"
      assert_equal 20, error.affected.site_id
    end

    it "rejects --timeout without --wait before any request" do
      fake = client
      assert_raises(ForgeCli::Error) { run_write("deploy", ["example.com", "--timeout", "60"], fake: fake) }
      assert_empty fake.calls
    end
  end

  describe "env-set" do
    it "masks the environment in the dry-run body" do
      run = run_write("env-set", ["example.com", "--set", "NEW_KEY=new-secret", "-d"])
      assert_includes run[:out], "APP_KEY=********"
      assert_includes run[:out], "NEW_KEY=********"
      (SECRETS + ["new-secret"]).each { |secret| refute_includes run[:out] + run[:err], secret }
    end

    it "masks the JSON dry-run body too" do
      run = run_write("env-set", ["example.com", "--set", "NEW_KEY=new-secret", "-d"], json: true)
      environment = JSON.parse(run[:out]).dig("data", "request", "body", "environment")
      assert_equal "APP_KEY=********\nDB_PASSWORD=********\n# note\nNEW_KEY=********\n", environment
    end

    it "shows raw values in the dry-run body with --reveal" do
      run = run_write("env-set", ["example.com", "--set", "NEW_KEY=new-secret", "-d", "--reveal"])
      assert_includes run[:out], "topsecret"
      assert_includes run[:out], "NEW_KEY=new-secret"
    end

    it "prints key names, never values, to stderr" do
      run = run_write("env-set", ["example.com", "--set", "NEW_KEY=v1", "--set", "APP_KEY=rotated", "--unset",
                                  "DB_PASSWORD", "-d"])
      assert_includes run[:err], "keys added: NEW_KEY"
      assert_includes run[:err], "keys removed: DB_PASSWORD"
      assert_includes run[:err], "keys changed: APP_KEY"
      %w[v1 rotated topsecret hunter2].each { |value| refute_includes run[:err], value }
    end

    it "applies --set and --unset in argument order and sends the environment key" do
      run = run_write("env-set", ["example.com", "--set", "A=1", "--unset", "A", "--set", "B=two words", "--cache",
                                  "--yes"])
      body = run[:client].performed.first.body
      assert_equal "APP_KEY=base64:topsecret\nDB_PASSWORD=\"hunter2 x\"\n# note\nB=\"two words\"\n", body[:environment]
      assert_equal true, body[:cache]
      refute body.key?(:queues)
      refute body.key?(:content)
    end

    it "prints no change and sends nothing when nothing changes" do
      run = run_write("env-set", ["example.com", "--unset", "MISSING", "--yes"])
      assert_empty run[:client].performed
      assert_equal "no change\n", run[:out]
      assert_nil run[:result]
    end

    it "treats a file that only adds a trailing newline as no change" do
      run = run_write("env-set", ["example.com", "--file", script_file(SECRET_ENV.chomp), "--yes"])
      assert_empty run[:client].performed
    end

    it "replaces the file from --stdin with --yes" do
      run = run_write("env-set", ["example.com", "--stdin", "--yes"], stdin: StringIO.new("ONLY=1\n"))
      assert_equal "ONLY=1\n", run[:client].performed.first.body[:environment]
      assert_includes run[:err], "keys removed: APP_KEY, DB_PASSWORD"
    end

    it "refuses --stdin without --yes" do
      fake = client
      assert_raises(ForgeCli::GuardRefused) do
        run_write("env-set", ["example.com", "--stdin"], stdin: StringIO.new("ONLY=1\n"), fake: fake)
      end
      assert_empty fake.performed
    end

    it "never echoes the response body" do
      run = run_write("env-set", ["example.com", "--set", "NEW_KEY=1", "--yes"], json: true)
      assert_equal({ "done" => true }, JSON.parse(run[:out])["data"])
      SECRETS.each { |secret| refute_includes run[:out], secret }
    end

    it "needs exactly one mode" do
      [["example.com"], ["example.com", "--stdin", "--set", "A=1"],
       ["example.com", "--file", "x", "--stdin"]].each do |argv|
        fake = client
        error = assert_raises(ForgeCli::Error) { run_write("env-set", argv, fake: fake) }
        assert_includes error.message, "exactly one of"
        assert_empty fake.calls
      end
    end

    it "rejects a malformed --set or key" do
      assert_raises(ForgeCli::Error) { run_write("env-set", ["example.com", "--set", "NOVALUE"]) }
      assert_raises(ForgeCli::Error) { run_write("env-set", ["example.com", "--set", "1BAD=x"]) }
    end
  end

  describe "deploy-script-set" do
    it "prints no change when the file matches, even with an extra trailing newline" do
      run = run_write("deploy-script-set", ["example.com", "--file", script_file("#{SCRIPT}\n"), "-d"])
      assert_equal "no change\n", run[:out]
      assert_empty run[:client].performed
    end

    it "treats an auto_source flip as a change" do
      run = run_write("deploy-script-set", ["example.com", "--file", script_file(SCRIPT), "--auto-source", "--yes"])
      assert_equal({ content: SCRIPT, auto_source: true }, run[:client].performed.first.body)
    end

    it "leaves auto_source out unless a flag is given" do
      run = run_write("deploy-script-set", ["example.com", "--stdin", "--yes"], stdin: StringIO.new("echo a\n"))
      assert_equal({ content: "echo a\n" }, run[:client].performed.first.body)
      assert_includes run[:err], "2 lines -> 1 lines"
    end

    it "refuses an empty script and a missing file before any request" do
      fake = client
      assert_raises(ForgeCli::Error) { run_write("deploy-script-set", ["example.com", "--stdin", "--yes"], fake: fake) }
      assert_raises(ForgeCli::Error) do
        run_write("deploy-script-set", ["example.com", "--file", "/nonexistent/forge-script", "--yes"], fake: fake)
      end
      assert_empty fake.calls
    end
  end
end
