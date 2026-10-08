# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "forge_cli/endpoints"

# Every request builder checked against the API snapshot in
# docs/forge-openapi.json: the path matches a template, the method exists on
# it, query keys are declared parameters, every body key is a property of the
# request schema, every required property is present, and values fit the
# declared types and enums. Refresh the snapshot, then run this file.
describe "Endpoints against docs/forge-openapi.json" do
  SNAPSHOT = JSON.parse(File.read(File.expand_path("../docs/forge-openapi.json", __dir__)))
  EP = ForgeCli::Endpoints

  # Module functions that build parts of requests rather than requests.
  HELPERS = %i[check_site_keys! compact_body events_query get job_body org_path segment server_path site_path write].freeze

  # Query keys the API honors but the snapshot does not declare.
  UNDECLARED_QUERY = { org_site: ["include"] }.freeze

  # One or more sample calls per builder; write builders get a minimal call and
  # one with every optional key, so each body key is checked.
  SAMPLES = {
    user: [-> { EP.user }],
    orgs: [-> { EP.orgs }],
    servers: [-> { EP.servers("my-org") }],
    server: [-> { EP.server("my-org", 10) }],
    org_sites: [-> { EP.org_sites("my-org") }],
    org_site: [-> { EP.org_site("my-org", 20) }],
    server_sites: [-> { EP.server_sites("my-org", 10) }],
    deployments: [-> { EP.deployments("my-org", 10, 20, size: 10) }],
    deployment: [-> { EP.deployment("my-org", 10, 20, 30) }],
    deployment_log: [-> { EP.deployment_log("my-org", 10, 20, 30) }],
    deployment_status: [-> { EP.deployment_status("my-org", 10, 20) }],
    deploy_script: [-> { EP.deploy_script("my-org", 10, 20) }],
    environment: [-> { EP.environment("my-org", 10, 20) }],
    domains: [-> { EP.domains("my-org", 10, 20) }],
    site_certificates: [-> { EP.site_certificates("my-org", 10, 20) }],
    site_log: EP::SITE_LOG_TYPES.map { |type| -> { EP.site_log("my-org", 10, 20, type) } },
    schemas: [-> { EP.schemas("my-org", 10) }],
    db_users: [-> { EP.db_users("my-org", 10) }],
    daemons: [-> { EP.daemons("my-org", 10) }],
    daemon_log: [-> { EP.daemon_log("my-org", 10, 30) }],
    firewall_rules: [-> { EP.firewall_rules("my-org", 10) }],
    server_log: [-> { EP.server_log("my-org", 10, "nginx-access") }],
    server_jobs: [-> { EP.server_jobs("my-org", 10) }],
    site_jobs: [-> { EP.site_jobs("my-org", 10, 20) }],
    server_job_output: [-> { EP.server_job_output("my-org", 10, 30) }],
    site_job_output: [-> { EP.site_job_output("my-org", 10, 20, 30) }],
    org_events: [-> { EP.org_events("my-org", size: 20) }],
    server_events: [-> { EP.server_events("my-org", 10, size: 20) }],
    event_output: [-> { EP.event_output("my-org", 10, 30) }],
    # writes
    deploy: [-> { EP.deploy("my-org", 10, 20) }],
    put_environment: [-> { EP.put_environment("my-org", 10, 20, content: "A=1\n") },
                      -> { EP.put_environment("my-org", 10, 20, content: "A=1\n", cache: true, queues: false) }],
    put_deploy_script: [-> { EP.put_deploy_script("my-org", 10, 20, content: "git pull\n") },
                        -> { EP.put_deploy_script("my-org", 10, 20, content: "git pull\n", auto_source: true) }],
    create_firewall_rule: [-> { EP.create_firewall_rule("my-org", 10, name: "ssh-office", type: "allow") }] +
      EP::FIREWALL_TYPES.map do |type|
        -> { EP.create_firewall_rule("my-org", 10, name: "ssh-office", type: type, port: 22, ip_address: "203.0.113.7") }
      end,
    delete_firewall_rule: [-> { EP.delete_firewall_rule("my-org", 10, 30) }],
    service_action: EP::SERVICE_ACTIONS.flat_map do |service, actions|
      actions.map do |action|
        -> { EP.service_action("my-org", 10, service, action: action, version: service == "php" ? "php84" : nil) }
      end
    end,
    server_action: EP::SERVER_ACTIONS.map { |action| -> { EP.server_action("my-org", 10, action: action) } },
    create_daemon: [-> { EP.create_daemon("my-org", 10, name: "worker", command: "php artisan queue:work", user: "forge", processes: 1) }] +
      EP::DAEMON_USERS.map do |user|
        lambda {
          EP.create_daemon("my-org", 10, name: "worker", command: "php artisan queue:work", user: user, processes: 2,
                                         directory: "/home/forge/example.com", site_id: 20, startsecs: 1,
                                         stopwaitsecs: 10, stopsignal: "SIGTERM")
        }
      end,
    delete_daemon: [-> { EP.delete_daemon("my-org", 10, 30) }],
    daemon_action: [-> { EP.daemon_action("my-org", 10, 30, action: "restart") }],
    create_server_job: EP::JOB_FREQUENCIES.map do |frequency|
      -> { EP.create_server_job("my-org", 10, command: "php artisan schedule:run", user: "forge", frequency: frequency) }
    end + [lambda {
      EP.create_server_job("my-org", 10, command: "php artisan schedule:run", user: "forge", frequency: "custom",
                                         name: "scheduler", cron: "0 * * * *", heartbeat: true)
    }],
    create_site_job: [-> { EP.create_site_job("my-org", 10, 20, command: "php artisan schedule:run", user: "forge", frequency: "minutely") },
                      lambda {
                        EP.create_site_job("my-org", 10, 20, command: "php artisan schedule:run", user: "forge",
                                                             frequency: "custom", name: "scheduler", cron: "0 * * * *", heartbeat: false)
                      }],
    delete_server_job: [-> { EP.delete_server_job("my-org", 10, 30) }],
    delete_site_job: [-> { EP.delete_site_job("my-org", 10, 20, 30) }],
    create_schema: [-> { EP.create_schema("my-org", 10, name: "app") },
                    -> { EP.create_schema("my-org", 10, name: "app", user: "app_user", password: "placeholder") }],
    delete_schema: [-> { EP.delete_schema("my-org", 10, 60) }],
    create_db_user: [-> { EP.create_db_user("my-org", 10, name: "app_user", password: "placeholder") },
                     lambda {
                       EP.create_db_user("my-org", 10, name: "app_user", password: "placeholder", database_ids: [60, 61],
                                                       read_only: true)
                     }],
    update_db_user: [-> { EP.update_db_user("my-org", 10, 70, password: "placeholder") },
                     -> { EP.update_db_user("my-org", 10, 70, database_ids: [60]) },
                     -> { EP.update_db_user("my-org", 10, 70, password: "placeholder", database_ids: []) }],
    delete_db_user: [-> { EP.delete_db_user("my-org", 10, 70) }],
    create_site: [-> { EP.create_site("my-org", 10, type: "laravel", name: "example.com") }] +
      EP::SITE_TYPES.map { |type| -> { EP.create_site("my-org", 10, type: type, name: "example.com") } } +
      EP::SOURCE_CONTROL_PROVIDERS.map do |provider|
        lambda {
          EP.create_site("my-org", 10, type: "laravel", name: "example.com", php_version: "php84",
                                       web_directory: "/public", source_control_provider: provider,
                                       repository: "acme/app", branch: "main", is_isolated: true,
                                       isolated_user: "app", zero_downtime_deployments: true,
                                       allow_wildcard_subdomains: true, www_redirect_type: "from-www")
        }
      end,
    update_site: [-> { EP.update_site("my-org", 10, 20, php_version: "php84") },
                  lambda {
                    EP.update_site("my-org", 10, 20, php_version: "php83", type: "laravel", directory: "/public",
                                                     root_path: "/home/forge/example.com", repository_branch: "main",
                                                     push_to_deploy: false, deployment_retention: 5)
                  }],
    delete_site: [-> { EP.delete_site("my-org", 10, 20) }],
    create_domain: EP::WWW_REDIRECT_TYPES.map do |www|
      -> { EP.create_domain("my-org", 10, 20, name: "www.example.com", www_redirect_type: www, allow_wildcard_subdomains: false) }
    end,
    delete_domain: [-> { EP.delete_domain("my-org", 10, 20, 80) }],
    domain_certificates: [-> { EP.domain_certificates("my-org", 10, 20, 80) }],
    issue_certificate: EP::CERT_VERIFICATION_METHODS.product(EP::CERT_KEY_TYPES).map do |method, key_type|
      -> { EP.issue_certificate("my-org", 10, 20, 80, verification_method: method, key_type: key_type) }
    end,
    delete_certificate: [-> { EP.delete_certificate("my-org", 10, 20, 80, 90) }]
  }.freeze

  # -- schema helpers ---------------------------------------------------------

  def deref(schema)
    while schema.is_a?(Hash) && schema["$ref"]
      schema = schema["$ref"].delete_prefix("#/").split("/").reduce(SNAPSHOT) { |node, key| node.fetch(key) }
    end
    schema
  end

  # $ref followed and allOf merged into one {properties, required} view.
  def resolve(schema)
    schema = deref(schema)
    return schema unless schema.is_a?(Hash) && schema["allOf"]

    parts = schema["allOf"].map { |part| resolve(part) }
    merged = schema.except("allOf")
    merged["properties"] = parts.reduce(schema["properties"] || {}) { |acc, part| acc.merge(part["properties"] || {}) }
    merged["required"] = parts.flat_map { |part| part["required"] || [] } + (schema["required"] || [])
    merged
  end

  def json_type(value)
    case value
    when nil then "null"
    when true, false then "boolean"
    when Integer then "integer"
    when Numeric then "number"
    when String then "string"
    when Array then "array"
    when Hash then "object"
    end
  end

  # Problems with value against schema, as strings; [] when it fits.
  def problems(value, schema, where)
    schema = resolve(schema)
    return [] unless schema.is_a?(Hash)

    alternatives = schema["anyOf"] || schema["oneOf"]
    if alternatives
      found = alternatives.map { |alt| problems(value, alt, where) }
      return found.any?(&:empty?) ? [] : ["#{where}: #{value.inspect} fits none of anyOf/oneOf"]
    end

    out = []
    types = Array(schema["type"])
    type = json_type(value)
    unless types.empty? || types.include?(type) || (type == "integer" && types.include?("number"))
      out << "#{where}: #{type} is not #{types.join('|')}"
    end
    if schema["enum"] && !schema["enum"].include?(value)
      out << "#{where}: #{value.inspect} is not one of #{schema['enum'].join(', ')}"
    end
    out.concat(object_problems(value, schema, where)) if value.is_a?(Hash)
    if value.is_a?(Array) && schema["items"]
      value.each_with_index { |item, i| out.concat(problems(item, schema["items"], "#{where}[#{i}]")) }
    end
    out
  end

  def object_problems(body, schema, where)
    properties = schema["properties"] || {}
    out = body.keys.map(&:to_s).reject { |key| properties.key?(key) }
              .map { |key| "#{where}: #{key} is not a property (#{properties.keys.join(', ')})" }
    out.concat((schema["required"] || []).reject { |key| body.key?(key.to_sym) || body.key?(key) }
                                          .map { |key| "#{where}: required #{key} is missing" })
    body.each do |key, value|
      out.concat(problems(value, properties[key.to_s], "#{where}.#{key}")) if properties.key?(key.to_s)
    end
    out
  end

  # The template the router would pick: a literal match beats a parameter.
  def template_for(path)
    SNAPSHOT["paths"].keys
                     .select { |template| Regexp.new("\\A#{Regexp.escape(template).gsub(/\\\{[^}]+\\\}/, '[^/]+')}\\z").match?(path) }
                     .min_by { |template| template.count("{") }
  end

  def query_problems(name, request, operation, path_item)
    params = (operation["parameters"] || []) + (path_item["parameters"] || [])
    declared = params.select { |p| p["in"] == "query" }.to_h { |p| [p["name"], p["schema"]] }
    request.query.flat_map do |key, value|
      next [] if UNDECLARED_QUERY.fetch(name, []).include?(key)
      next ["query #{key} is not a declared parameter"] unless declared.key?(key)

      schema = resolve(declared[key])
      # explode: false arrays accept a single value, e.g. sort=-created_at
      schema = schema["items"] if schema.is_a?(Hash) && schema["type"] == "array" && !value.is_a?(Array)
      problems(value, schema, "query #{key}")
    end
  end

  def body_problems(request, operation)
    body_spec = operation["requestBody"]
    return(body_spec&.dig("required") ? ["body is required"] : []) if request.body.nil?
    return ["sends a body, but the operation takes none"] unless body_spec

    schema = body_spec.dig("content", "application/json", "schema")
    return ["no application/json request schema"] unless schema

    problems(request.body, schema, "body")
  end

  # -- specs ------------------------------------------------------------------

  it "has a sample for every builder" do
    builders = EP.singleton_methods - HELPERS
    assert_equal builders.sort, SAMPLES.keys.sort
  end

  SAMPLES.each do |name, calls|
    it "#{name} matches the snapshot" do
      calls.each do |call|
        request = call.call
        template = template_for(request.path)
        refute_nil template, "#{name}: #{request.path} matches no path in the snapshot"
        path_item = SNAPSHOT["paths"][template]
        operation = path_item[request.method.downcase]
        refute_nil operation, "#{name}: #{request.method} is not defined on #{template}"

        found = query_problems(name, request, operation, path_item) + body_problems(request, operation)
        assert_empty found, "#{name} (#{request.method} #{template}):\n  #{found.join("\n  ")}"
      end
    end
  end

  # The CLI's own validation tables must match the snapshot's enums exactly,
  # so a value the API drops or adds shows up here, not as a live 422.
  describe "validation tables" do
    def enum_of(path, method, property)
      schema = resolve(SNAPSHOT.dig("paths", path, method, "requestBody", "content", "application/json", "schema"))
      resolve(schema["properties"][property])["enum"]
    end

    SERVER_TEMPLATE = "/orgs/{organization}/servers/{server}"

    it "SERVICE_ACTIONS lists every service endpoint and its action enum" do
      services = SNAPSHOT["paths"].keys.filter_map { |p| p[%r{\A#{Regexp.escape(SERVER_TEMPLATE)}/services/([^/{}]+)/actions\z}, 1] }
      assert_equal services.sort, EP::SERVICE_ACTIONS.keys.sort
      EP::SERVICE_ACTIONS.each do |service, actions|
        assert_equal enum_of("#{SERVER_TEMPLATE}/services/#{service}/actions", "post", "action").sort, actions.sort, service
      end
    end

    it "SERVER_ACTIONS, FIREWALL_TYPES, DAEMON_USERS, and JOB_FREQUENCIES match their enums" do
      assert_equal enum_of("#{SERVER_TEMPLATE}/actions", "post", "action").sort, EP::SERVER_ACTIONS.sort
      assert_equal enum_of("#{SERVER_TEMPLATE}/firewall-rules", "post", "type").sort, EP::FIREWALL_TYPES.sort
      assert_equal enum_of("#{SERVER_TEMPLATE}/background-processes", "post", "user").sort, EP::DAEMON_USERS.sort
      assert_equal enum_of("#{SERVER_TEMPLATE}/scheduled-jobs", "post", "frequency").sort, EP::JOB_FREQUENCIES.sort
    end

    SITE_TEMPLATE = "#{SERVER_TEMPLATE}/sites/{site}"

    it "site, domain, and certificate tables match their enums" do
      assert_equal enum_of("#{SERVER_TEMPLATE}/sites", "post", "type").sort, EP::SITE_TYPES.sort
      assert_equal enum_of("#{SERVER_TEMPLATE}/sites", "post", "php_version").sort, EP::PHP_VERSIONS.sort
      assert_equal enum_of("#{SITE_TEMPLATE}/domains", "post", "www_redirect_type").sort, EP::WWW_REDIRECT_TYPES.sort
      letsencrypt = resolve(SNAPSHOT.dig("paths", "#{SITE_TEMPLATE}/domains/{domainRecord}/certificates", "post",
                                         "requestBody", "content", "application/json", "schema"))
                    .dig("properties", "letsencrypt", "properties")
      assert_equal resolve(letsencrypt["verification_method"])["enum"].sort, EP::CERT_VERIFICATION_METHODS.sort
      assert_equal resolve(letsencrypt["key_type"])["enum"].sort, EP::CERT_KEY_TYPES.sort
    end

    # The CLI offers a subset of providers; each must still be one the API knows.
    it "SOURCE_CONTROL_PROVIDERS is a subset of the provider enum" do
      known = SNAPSHOT.dig("components", "schemas", "SourceControlProvider", "enum")
      assert_empty EP::SOURCE_CONTROL_PROVIDERS - known
    end

    # Open question 7: domain_mode is anyOf string | CreateSiteDomainMode, so the
    # generic checker accepts any string. Pin it to the named enum, and name
    # (anyOf string | string) to the domain itself.
    it "settles site-create domain_mode as the custom member of its enum" do
      assert_includes SNAPSHOT.dig("components", "schemas", "CreateSiteDomainMode", "enum"), "custom"
      body = EP.create_site("my-org", 10, type: "laravel", name: "example.com").body
      assert_equal({ type: "laravel", name: "example.com", domain_mode: "custom" }, body)
    end

    # Open question 7: the request schema is an allOf whose first part types
    # ip_address as an untyped object and whose second narrows it to string.
    # Merged, it is a string; an object is rejected.
    it "settles the firewall ip_address as a string" do
      schema = resolve(SNAPSHOT.dig("paths", "#{SERVER_TEMPLATE}/firewall-rules", "post", "requestBody", "content",
                                    "application/json", "schema"))
      assert_equal "string", schema.dig("properties", "ip_address", "type")
      found = problems({ name: "x", type: "allow", ip_address: { address: "203.0.113.7" } }, schema, "body")
      assert_includes found, "body.ip_address: object is not string"
    end
  end

  describe "the checker itself" do
    it "flags an unknown body key, a missing required key, a bad type, and a bad enum" do
      schema = { "type" => "object", "required" => %w[a], "properties" => {
        "a" => { "type" => "string" }, "b" => { "type" => "string", "enum" => %w[x y] }
      } }
      found = problems({ b: "z", c: 1 }, schema, "body")
      assert_equal 3, found.size
      assert(found.any? { |p| p.include?("c is not a property") })
      assert(found.any? { |p| p.include?("required a is missing") })
      assert(found.any? { |p| p.include?("is not one of x, y") })
      assert_equal ["body.a: integer is not string"], problems({ a: 1 }, schema, "body")
    end

    it "checks array items, so database ids must be integers" do
      schema = { "type" => "array", "items" => { "type" => "integer" } }
      assert_empty problems([60, 61], schema, "ids")
      assert_equal ["ids[1]: string is not integer"], problems([60, "61"], schema, "ids")
    end

    it "prefers a literal path over a parameter" do
      assert_equal "/orgs/{organization}/servers/{server}/sites/{site}/deployments/status",
                   template_for("/orgs/my-org/servers/10/sites/20/deployments/status")
    end

    it "rejects a body on an operation that takes none" do
      operation = SNAPSHOT["paths"][template_for(EP.deploy("my-org", 10, 20).path)]["post"]
      request = ForgeCli::Request.new(method: "POST", path: "/x", body: { a: 1 })
      assert_equal ["sends a body, but the operation takes none"], body_problems(request, operation)
    end
  end
end
