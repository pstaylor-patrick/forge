# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/fake_client"
require_relative "support/tty_input"
require "json"
require "stringio"
require "tempfile"
require "forge_cli/browser"
require "forge_cli/context"
require "forge_cli/formatter"

# Write commands against canned responses. Nothing here opens a socket: every
# "sent" request lands in FakeClient#performed.
describe "write commands" do
  SERVER = "/orgs/my-org/servers/10"
  SITE = "#{SERVER}/sites/20"
  SITE_AFFECTED = ForgeCli::Affected.new(org: "my-org", server_id: 10, site_id: 20)
  SERVER_AFFECTED = ForgeCli::Affected.new(org: "my-org", server_id: 10)
  SECRET_ENV = "APP_KEY=base64:topsecret\nDB_PASSWORD=\"hunter2 x\"\n# note\n"
  SCRIPT = "cd /home/forge/example.com\ngit pull origin main\n"
  SECRETS = %w[topsecret hunter2].freeze

  def client(deployment_statuses: %w[finished])
    statuses = deployment_statuses.dup
    FakeClient.new(
      fetch_all: { "/orgs/my-org/servers" => [{ id: "10", type: "servers", attributes: { name: "web-1", php_version: "php84" } }],
                   "/orgs/my-org/sites" => [{ id: "20", type: "sites", attributes: { name: "example.com" },
                                              relationships: { server: { data: { type: "servers", id: "10" } } } }],
                   "#{SERVER}/firewall-rules" => [{ id: "45", type: "rules", attributes: { name: "ssh-office", port: "22" } }],
                   "#{SERVER}/background-processes" => [{ id: "30", type: "backgroundProcesses",
                                                          attributes: { command: "php artisan queue:work" } }],
                   "#{SERVER}/scheduled-jobs" => [{ id: "40", type: "scheduledJobs", attributes: { name: "scheduler", command: "php artisan schedule:run" } },
                                                  { id: "41", type: "scheduledJobs", attributes: { name: nil, command: "php artisan backup" } }],
                   "#{SITE}/scheduled-jobs" => [{ id: "50", type: "scheduledJobs", attributes: { name: "site-job", command: "php artisan inspire" } }] },
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
    "deploy-script-set" => [["example.com", "--stdin", "-d"], "PUT", "#{SITE}/deployments/script"],
    "firewall-create" => [["--name", "probe", "--port", "8443", "--ip", "203.0.113.7", "-d"], "POST",
                          "#{SERVER}/firewall-rules"],
    "firewall-delete" => [["ssh-office", "-d"], "DELETE", "#{SERVER}/firewall-rules/45"],
    "service" => [%w[nginx stop -d], "POST", "#{SERVER}/services/nginx/actions"],
    "reboot" => [["-d"], "POST", "#{SERVER}/actions"],
    "daemon-create" => [["--name", "probe", "--command", "php artisan probe", "-d"], "POST",
                        "#{SERVER}/background-processes"],
    "daemon-delete" => [%w[30 -d], "DELETE", "#{SERVER}/background-processes/30"],
    "daemon-restart" => [%w[30 -d], "POST", "#{SERVER}/background-processes/30/actions"],
    "job-create" => [["--command", "php artisan schedule:run", "--frequency", "minutely", "-d"], "POST",
                     "#{SERVER}/scheduled-jobs"],
    "job-delete" => [%w[scheduler -d], "DELETE", "#{SERVER}/scheduled-jobs/40"]
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
        refute_includes run[:err], "to confirm"
      end
    end
  end

  describe "guarded commands" do
    # name => [argv, method, path, token typed at the prompt, affected]
    GUARDED = {
      "env-set" => [["example.com", "--set", "NEW_KEY=1"], "PUT", "#{SITE}/environment", "example.com", SITE_AFFECTED],
      "deploy-script-set" => [["example.com", "--file", :script], "PUT", "#{SITE}/deployments/script", "example.com",
                              SITE_AFFECTED],
      "firewall-delete" => [["ssh-office"], "DELETE", "#{SERVER}/firewall-rules/45", "ssh-office", SERVER_AFFECTED],
      "service" => [%w[mysql stop], "POST", "#{SERVER}/services/mysql/actions", "web-1", SERVER_AFFECTED],
      "reboot" => [[], "POST", "#{SERVER}/actions", "web-1", SERVER_AFFECTED],
      "daemon-delete" => [["30"], "DELETE", "#{SERVER}/background-processes/30", "30", SERVER_AFFECTED],
      "job-delete" => [["scheduler"], "DELETE", "#{SERVER}/scheduled-jobs/40", "scheduler", SERVER_AFFECTED]
    }.freeze

    GUARDED.each do |name, (argv, method, path, token, affected)|
      it "#{name}: refuses a non-TTY stdin without --yes and sends nothing" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        fake = client
        assert_raises(ForgeCli::GuardRefused) { run_write(name, args, fake: fake) }
        assert_empty fake.performed
      end

      it "#{name}: sends exactly one #{method} with --yes and returns what it affected" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        run = run_write(name, args + ["--yes"])
        assert_equal 1, run[:client].performed.size
        request = run[:client].performed.first
        assert_equal method, request.method
        assert_equal path, request.path
        assert_equal affected, run[:result]
      end

      it "#{name}: sends after #{token} is typed on a TTY" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        run = run_write(name, args, stdin: TtyInput.new("#{token}\n"))
        assert_equal 1, run[:client].performed.size
        assert_includes run[:err], "Type #{token} to confirm"
      end

      it "#{name}: aborts on a wrong name and sends nothing" do
        args = argv.map { |a| a == :script ? script_file("echo new\n") : a }
        fake = client
        assert_raises(ForgeCli::Aborted) { run_write(name, args, stdin: TtyInput.new("#{token}x\n"), fake: fake) }
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

  # Asserts a usage error raised before any request (no fetch, no perform).
  def assert_rejected(name, argv, message)
    fake = client
    error = assert_raises(ForgeCli::Error) { run_write(name, argv, fake: fake) }
    assert_includes error.message, message
    assert_empty fake.calls
    assert_empty fake.performed
  end

  def sent(run) = run[:client].performed.map { |r| [r.method, r.path, r.body] }

  describe "firewall-create" do
    it "sends name, type, port as a string, and ip_address as a string, unguarded" do
      run = run_write("firewall-create", ["--name", "probe", "--port", "8443", "--ip", "203.0.113.7"])
      assert_equal [["POST", "#{SERVER}/firewall-rules",
                     { name: "probe", type: "allow", port: "8443", ip_address: "203.0.113.7" }]], sent(run)
      assert_equal SERVER_AFFECTED, run[:result]
    end

    it "leaves port and ip out when not given, and takes --type deny" do
      run = run_write("firewall-create", ["--name", "block-all", "--type", "deny"])
      assert_equal({ name: "block-all", type: "deny" }, run[:client].performed.first.body)
    end

    it "rejects a missing or long name, a bad type, and a bad port before any request" do
      assert_rejected("firewall-create", ["--port", "22"], "--name is required")
      assert_rejected("firewall-create", ["--name", "x" * 51], "at most 50")
      assert_rejected("firewall-create", ["--name", "x", "--type", "reject"], "--type must be one of allow, deny")
      assert_rejected("firewall-create", ["--name", "x", "--port", "ssh"], "--port must be")
    end
  end

  describe "firewall-delete" do
    it "names the rule and server in the prompt" do
      run = run_write("firewall-delete", ["45"], stdin: TtyInput.new("ssh-office\n"))
      assert_includes run[:err], "delete firewall rule 45 (ssh-office) on server web-1"
      assert_equal [["DELETE", "#{SERVER}/firewall-rules/45", nil]], sent(run)
    end

    it "fails with NotFoundError for an unknown rule and sends nothing" do
      fake = client
      assert_raises(ForgeCli::NotFoundError) { run_write("firewall-delete", ["nope", "--yes"], fake: fake) }
      assert_empty fake.performed
    end
  end

  describe "service" do
    it "sends restart as reboot without a guard" do
      run = run_write("service", %w[nginx restart])
      assert_equal [["POST", "#{SERVER}/services/nginx/actions", { action: "reboot" }]], sent(run)
      assert_equal SERVER_AFFECTED, run[:result]
    end

    it "defaults the php version to the server's php_version" do
      run = run_write("service", %w[php restart])
      assert_equal({ action: "reboot", version: "php84" }, run[:client].performed.first.body)
    end

    it "takes --php-version and reload for php" do
      run = run_write("service", %w[php reload --php-version php83])
      assert_equal({ action: "reload", version: "php83" }, run[:client].performed.first.body)
    end

    it "accepts every action in the table for every service" do
      ForgeCli::Commands::Service.actions.each do |service, actions|
        actions.each do |action|
          run = run_write("service", [service, action, "--yes"])
          assert_equal "#{SERVER}/services/#{service}/actions", run[:client].performed.first.path
        end
      end
    end

    it "validates service and action against the table before any request" do
      assert_rejected("service", %w[redis stop], "redis does not support 'stop'; it supports restart, reboot")
      assert_rejected("service", %w[supervisor reload], "supervisor does not support 'reload'")
      assert_rejected("service", %w[nginx reload], "nginx does not support 'reload'")
      assert_rejected("service", %w[apache restart], "unknown service 'apache'")
      assert_rejected("service", %w[nginx restart --php-version php84], "only applies to the php service")
      assert_rejected("service", %w[php restart --php-version 8.4], "must look like php84")
      assert_rejected("service", %w[nginx], "missing SERVICE and ACTION")
    end

    it "fails when the server reports no php_version and none is given" do
      fake = FakeClient.new(fetch_all: { "/orgs/my-org/servers" => [{ id: "10", attributes: { name: "web-1", php_version: nil } }] })
      error = assert_raises(ForgeCli::Error) { run_write("service", %w[php restart], fake: fake) }
      assert_includes error.message, "--php-version"
      assert_empty fake.performed
    end
  end

  describe "reboot" do
    it "sends reboot by default and power-cycle with --power-cycle" do
      assert_equal [["POST", "#{SERVER}/actions", { action: "reboot" }]], sent(run_write("reboot", ["--yes"]))
      assert_equal({ action: "power-cycle" }, run_write("reboot", ["--power-cycle", "--yes"])[:client].performed.first.body)
    end

    it "shows power-cycle in the dry run" do
      run = run_write("reboot", ["--power-cycle", "-d"])
      assert_includes run[:out], "\"power-cycle\""
    end
  end

  describe "daemon-create" do
    it "defaults user to forge and processes to 1, unguarded" do
      run = run_write("daemon-create", ["--name", "probe", "--command", "php artisan probe"])
      assert_equal [["POST", "#{SERVER}/background-processes",
                     { name: "probe", command: "php artisan probe", user: "forge", processes: 1 }]], sent(run)
      assert_equal SERVER_AFFECTED, run[:result]
    end

    it "sends every optional key and resolves --site to its id" do
      run = run_write("daemon-create", ["--name", "w", "--command", "c", "--user", "root", "--processes", "3",
                                        "--directory", "/home/forge/example.com", "--site", "example.com",
                                        "--startsecs", "0", "--stopwaitsecs", "15", "--stopsignal", "SIGINT"])
      assert_equal({ name: "w", command: "c", user: "root", processes: 3, directory: "/home/forge/example.com",
                     site_id: 20, startsecs: 0, stopwaitsecs: 15, stopsignal: "SIGINT" },
                   run[:client].performed.first.body)
    end

    it "rejects missing name or command, a bad user, and a bad count before any request" do
      assert_rejected("daemon-create", ["--command", "c"], "--name is required")
      assert_rejected("daemon-create", ["--name", "n"], "--command is required")
      assert_rejected("daemon-create", ["--name", "n", "--command", "c", "--user", "www-data"], "--user must be one of")
      assert_rejected("daemon-create", ["--name", "n", "--command", "c", "--processes", "0"], "--processes")
    end
  end

  describe "daemon-delete and daemon-restart" do
    it "daemon-delete shows the command in the prompt and takes the id as the token" do
      run = run_write("daemon-delete", ["30"], stdin: TtyInput.new("30\n"))
      assert_includes run[:err], "delete background process 30 (php artisan queue:work)"
      assert_equal [["DELETE", "#{SERVER}/background-processes/30", nil]], sent(run)
    end

    it "daemon-restart sends the restart action without a guard" do
      run = run_write("daemon-restart", ["30"])
      assert_equal [["POST", "#{SERVER}/background-processes/30/actions", { action: "restart" }]], sent(run)
      assert_equal SERVER_AFFECTED, run[:result]
    end

    it "rejects a non-numeric id and an unknown id without sending" do
      fake = client
      assert_raises(ForgeCli::Error) { run_write("daemon-restart", ["worker"], fake: fake) }
      assert_raises(ForgeCli::NotFoundError) { run_write("daemon-restart", ["99"], fake: fake) }
      assert_empty fake.performed
    end
  end

  describe "job-create" do
    it "schedules a server job with user forge, unguarded" do
      run = run_write("job-create", ["--command", "php artisan schedule:run", "--frequency", "minutely"])
      assert_equal [["POST", "#{SERVER}/scheduled-jobs",
                     { command: "php artisan schedule:run", user: "forge", frequency: "minutely" }]], sent(run)
      assert_equal SERVER_AFFECTED, run[:result]
    end

    it "schedules a site job with --site and sends custom cron, name, and heartbeat" do
      run = run_write("job-create", ["--command", "x", "--frequency", "custom", "--cron", "0 * * * *", "--name", "hourly",
                                     "--heartbeat", "--user", "root", "--site", "example.com"])
      assert_equal [["POST", "#{SITE}/scheduled-jobs",
                     { command: "x", user: "root", frequency: "custom", name: "hourly", cron: "0 * * * *",
                       heartbeat: true }]], sent(run)
      assert_equal SITE_AFFECTED, run[:result]
    end

    it "needs --cron exactly when the frequency is custom, checked before any request" do
      assert_rejected("job-create", ["--command", "x", "--frequency", "custom"], "--frequency custom needs --cron")
      assert_rejected("job-create", ["--command", "x", "--frequency", "hourly", "--cron", "0 * * * *"],
                      "--cron only applies with --frequency custom")
    end

    it "rejects a missing command or frequency and an unknown frequency before any request" do
      assert_rejected("job-create", ["--frequency", "hourly"], "--command is required")
      assert_rejected("job-create", ["--command", "x"], "--frequency is required")
      assert_rejected("job-create", ["--command", "x", "--frequency", "daily"], "--frequency must be one of")
    end
  end

  describe "job-delete" do
    it "uses the id as the token for an unnamed job" do
      run = run_write("job-delete", ["41"], stdin: TtyInput.new("41\n"))
      assert_includes run[:err], "Type 41 to confirm"
      assert_includes run[:err], "41 (php artisan backup)"
      assert_equal [["DELETE", "#{SERVER}/scheduled-jobs/41", nil]], sent(run)
    end

    it "deletes a site job with --site and returns the site" do
      run = run_write("job-delete", ["site-job", "--site", "example.com", "--yes"])
      assert_equal [["DELETE", "#{SITE}/scheduled-jobs/50", nil]], sent(run)
      assert_equal SITE_AFFECTED, run[:result]
    end
  end
end
